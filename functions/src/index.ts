import * as admin from "firebase-admin";
import * as crypto from "node:crypto";
import {inflateSync} from "node:zlib";
import {onCall, HttpsError, CallableRequest} from "firebase-functions/v2/https";
import {defineSecret, defineString} from "firebase-functions/params";
import {log, warn} from "firebase-functions/logger";
import {GoogleAuth} from "google-auth-library";

admin.initializeApp();

const db = admin.firestore();
const geminiApiKey = defineSecret("GEMINI_API_KEY");
const appStoreKeyId = defineSecret("APP_STORE_KEY_ID");
const appStoreIssuerId = defineSecret("APP_STORE_ISSUER_ID");
const appStorePrivateKey = defineSecret("APP_STORE_PRIVATE_KEY");
const geminiTextModel = defineString("GEMINI_TEXT_MODEL", {
  default: "gemini-2.5-flash",
  description: "Gemini model for text/specs generation",
});
const geminiImageModel = defineString("GEMINI_IMAGE_MODEL", {
  default: "gemini-2.5-flash-image",
  description: "Gemini model for image generation",
});

/** 後端版本，每次修改 functions 時同步遞增（與 package.json version 保持一致） */
const FUNCTIONS_VERSION = "1.3.1";

// ── auth helper ──────────────────────────────────────────────────────────────

/**
 * 取得已驗證的 UID。
 *
 * 優先使用 SDK 內建的 request.auth；若為 null（v2 callable 已知 edge case），
 * 則手動從 Authorization header 解析並驗證 ID token。
 */
async function resolveUid(request: CallableRequest): Promise<string> {
  if (request.auth) {
    return request.auth.uid;
  }

  // request.auth is null — try manual fallback
  const authHeader = request.rawRequest?.headers?.authorization;
  if (!authHeader || !authHeader.startsWith("Bearer ")) {
    warn("resolveUid: no auth header found", {
      hasRawRequest: !!request.rawRequest,
      headers: request.rawRequest?.headers
        ? Object.keys(request.rawRequest.headers)
        : [],
    });
    throw new HttpsError(
      "unauthenticated",
      "No Authorization header. Please sign in."
    );
  }

  const idToken = authHeader.split("Bearer ")[1];
  try {
    const decoded = await admin.auth().verifyIdToken(idToken);
    log("resolveUid: manual token verify OK", {uid: decoded.uid});
    return decoded.uid;
  } catch (e) {
    warn("resolveUid: manual token verify failed", {error: String(e)});
    throw new HttpsError(
      "unauthenticated",
      `Token verification failed: ${String(e).slice(0, 200)}`
    );
  }
}

// ── creditHistory helper ─────────────────────────────────────────────────────

function writeCreditHistory(
  tx: admin.firestore.Transaction,
  uid: string,
  entry: {
    type: "earned" | "spent" | "refund";
    amount: number;
    reason: string;
  }
) {
  const histRef = db
    .collection("users")
    .doc(uid)
    .collection("creditHistory")
    .doc();
  tx.set(histRef, {
    ...entry,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}

// ── generateStickerSpecs ────────────────────────────────────────────────────
//
// 1. 驗證 Firebase Auth
// 2. 呼叫 Gemini 2.0 Flash（文字）取得 8 組貼圖規格
// 3. 回傳 specs（不扣點，Spec 預覽免費）

export const generateStickerSpecs = onCall(
  {
    region: "asia-east1",
    timeoutSeconds: 60,
    memory: "512MiB",
    secrets: [geminiApiKey],
    invoker: "public",
    enforceAppCheck: false,
  },
  async (request) => {
    // ★ 此行出現在 Firebase Logs = Cloud Run IAM 通過，function 程式碼有執行
    // 若 UNAUTHENTICATED 錯誤時此行消失 = IAM 攔截，需重新部署 invoker:public
    log("generateStickerSpecs: invoked", {
      hasAuth: !!request.auth,
      hasAuthHeader: !!request.rawRequest?.headers?.authorization,
      hasAppCheck: !!request.app,
    });
    if (!request.app) {
      warn("generateStickerSpecs: App Check token missing (App Distribution build?)");
    }
    const uid = await resolveUid(request);
    log("generateStickerSpecs: auth OK", {uid});

    const {
      photoBase64,
      categoryIds: rawCategoryIds,
      customStyleDesc,
      customEmotionDesc,
      enhancePersonFeatures,
    } = request.data as {
      photoBase64: string;
      categoryIds?: string[];
      customStyleDesc?: string;
      customEmotionDesc?: string;
      enhancePersonFeatures?: boolean;
    };

    if (!photoBase64) {
      throw new HttpsError("invalid-argument", "photoBase64 is required.");
    }

    // 情感類別 → 預設 8 種或由 client 指定（1–12 種）
    const DEFAULT_CATEGORY_IDS = [
      "greeting", "praise", "surprise", "awkward",
      "angry", "happy", "thinking", "farewell",
    ];
    const ids: string[] =
      Array.isArray(rawCategoryIds) && rawCategoryIds.length >= 1
        ? rawCategoryIds.slice(0, 12)
        : DEFAULT_CATEGORY_IDS;

    const CATEGORY_HINTS: Record<string, string> = {
      greeting:  "cheerfully waving hello",
      praise:    "excited thumbs-up with sparkles",
      surprise:  "shocked wide eyes, question marks",
      awkward:   "embarrassed blushing, sweat drop",
      angry:     "angry frowning with flames",
      happy:     "joyful laughing, rainbow confetti",
      thinking:  "thoughtful chin-rubbing, thought bubble",
      farewell:  "waving goodbye with sunglasses",
      shy:       "shy blushing, covering face gently",
      cool:      "smug cool confident sunglasses expression",
      tired:     "tired droopy eyes, yawning heavily",
      cry:       "crying tears flowing dramatically",
      love:      "loving warm smile, heart eyes, rosy cheeks",
      excited:   "star-struck excitement, jumping with joy",
      scared:    "terrified wide eyes, trembling in fear",
      mischief:  "playful mischievous wink, sticking out tongue",
      sleepy:    "half-closed droopy eyes, dozing off, ZZZ bubble",
      beg:       "puppy dog eyes, clasped hands pleading desperately",
      worried:   "anxious sweating, furrowed brows, trembling nervously",
      hungry:    "drooling mouth, stomach growling, starving expression",
      celebrate: "party popper, confetti raining, cheering with both arms up",
      no:        "shaking head firmly, crossed arms, X gesture refusing",
      encourage: "pumping fist, determined face, cheering someone on",
      pain:      "completely overwhelmed, spinning dizzy eyes, breaking down",
    };

    const categoryList = ids
      .map((id) => JSON.stringify({
        categoryId: id,
        promptHint: CATEGORY_HINTS[id] ?? id,
      }))
      .join(", ");

    // ── 呼叫 Gemini 文字 API ────────────────────────────────────────────────
    const apiKey = geminiApiKey.value();
    const textModel = geminiTextModel.value();
    const endpoint =
      "https://generativelanguage.googleapis.com/v1beta" +
      `/models/${textModel}:generateContent?key=${apiKey}`;

    // Pro 自訂描述提示（若有）
    const proHints: string[] = [];
    if (customStyleDesc && customStyleDesc.trim().length > 0) {
      proHints.push(
        `🎨 使用者指定視覺風格：「${customStyleDesc.trim()}」` +
        `（請將此風格融入 emotion 描述與 bgColor 搭配，體現在每張貼圖設計中）`
      );
    }
    if (customEmotionDesc && customEmotionDesc.trim().length > 0) {
      proHints.push(
        `🎭 使用者指定情緒氛圍：「${customEmotionDesc.trim()}」` +
        `（請讓此情緒氛圍貫穿所有貼圖設計，但各類別仍保有各自的個性變化）`
      );
    }
    const proHintSection = proHints.length > 0
      ? `\n\n✨ 使用者特別指定（優先遵循）：\n${proHints.join("\n")}\n`
      : "";

    // Pro 人物特徵強化：要求 Gemini 分析並回傳人物特徵
    const featureAnalysisSection = enhancePersonFeatures
      ? `\n\n🔍 人物特徵分析任務（必須執行）：` +
        `請仔細觀察照片中人物的外觀，分析以下特徵（英文描述，逗號分隔，簡潔）：` +
        `眼睛大小與形狀、鼻型、嘴唇厚薄、臉型、髮型髮色、其他明顯特徵（耳朵、眉毛等）。` +
        `\n\n⚠️ 回傳格式必須改為 JSON 物件（非陣列），包含兩個欄位：` +
        `\n- "specs": 貼圖規格陣列（格式同上）` +
        `\n- "personFeatures": 人物特徵英文字串（例如："small single-eyelid eyes, flat wide nose, full lips, round face, short wavy black hair"）` +
        `\n\n範例格式：{"specs":[{"categoryId":"greeting",...}],"personFeatures":"large eyes, high nose, thin lips, oval face, long straight black hair"}\n`
      : "";

    const body = {
      contents: [
        {
          parts: [
            {
              text:
                "你是一位創意 LINE 貼圖設計師，擅長根據照片人物的個性與氛圍，" +
                "設計出最適合的貼圖情感組合。\n\n" +
                "請仔細觀察照片中人物的外型、氣質、表情與場景，" +
                "依照以下情感類別清單（按順序），為他們設計專屬的 LINE 貼圖規格。" +
                proHintSection +
                featureAnalysisSection + "\n\n" +
                `情感類別清單：[${categoryList}]\n\n` +
                "每個類別設計一張貼圖，" +
                (enhancePersonFeatures
                  ? "回傳格式：JSON 物件，包含 \"specs\" 陣列與 \"personFeatures\" 字串（見上方要求）。"
                  : "輸出格式：僅回傳 JSON 陣列") +
                `（${ids.length} 個物件，順序與清單一致），每個物件包含：\n` +
                '- "categoryId": 對應情感類別 id（原樣回傳，不可修改）\n' +
                '- "text": 繁體中文標語（2–6 字，口語化有趣，適合貼圖）\n' +
                '- "emotion": 英文情感描述（用於繪製卡通表情，必須緊密基於此 categoryId 對應的 promptHint，僅描述表情與肢體動作，禁止加入外觀特徵如眼鏡、眉毛形狀等，禁止混入其他類別的情緒描述）\n' +
                '- "bgColor": 背景色描述（英文色名 + hex，例如 "coral red #FF6B6B"）\n\n' +
                "⚠️ 重要：每個物件的 emotion 必須完整反映該 categoryId 的情緒特徵（以 promptHint 為主體），不可將不同情緒混用，不可包含人物外觀特徵（眼鏡、眉型、髮型等屬於外觀，不屬於情緒描述）。\n\n" +
                "範例格式（不要照抄，請根據照片與 promptHint 創作）：\n" +
                '[{"categoryId":"greeting","text":"哈囉！","emotion":"cheerfully waving hello, big smile","bgColor":"warm peach #F4A261"},{"categoryId":"worried","text":"好擔心","emotion":"anxious sweating, furrowed brows, trembling nervously","bgColor":"pale yellow #FFFACD"},{"categoryId":"angry","text":"哼！","emotion":"angry frowning with flames, clenched fists","bgColor":"fiery red #FF6B6B"}]',
            },
            {
              inlineData: {
                mimeType: "image/jpeg",
                data: photoBase64,
              },
            },
          ],
        },
      ],
    };

    const res = await fetch(endpoint, {
      method: "POST",
      headers: {"Content-Type": "application/json"},
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(50000),
    });

    if (!res.ok) {
      const errText = await res.text();
      throw new HttpsError(
        "internal",
        `Gemini text API error ${res.status}: ${errText.slice(0, 300)}`
      );
    }

    const json = (await res.json()) as {
      candidates?: Array<{content: {parts: Array<{text?: string}>}; finishReason?: string}>;
      promptFeedback?: {blockReason?: string};
    };

    // Gemini 因版權/安全審查封鎖請求時，candidates 為空或 finishReason=SAFETY/COPYRIGHT
    const blockReason = json.promptFeedback?.blockReason
      ?? json.candidates?.[0]?.finishReason;
    if (!json.candidates?.length || blockReason === "SAFETY" || blockReason === "OTHER" || blockReason === "PROHIBITED_CONTENT" || blockReason === "COPYRIGHT") {
      throw new HttpsError(
        "invalid-argument",
        `Gemini blocked the request (reason: ${blockReason ?? "no candidates"}). ` +
        "Please avoid copyrighted brand names or sensitive terms in style/emotion descriptions."
      );
    }

    const text = json.candidates?.[0]?.content?.parts
      ?.map((p) => p.text ?? "")
      .join("") ?? "";

    // 確保每個 spec 的 categoryId 與請求的 ids[i] 一致，
    // 並以 CATEGORY_HINTS 作為 emotion 的權威來源（防止 Gemini 混入其他情緒或複製範例文字）。
    const normalizeSpecs = (arr: unknown[]): unknown[] =>
      arr.slice(0, ids.length).map((item, i) => {
        const spec = item as Record<string, unknown>;
        const expectedId = ids[i];
        if (spec["categoryId"] !== expectedId) {
          log(`normalizeSpecs: fixing spec[${i}] categoryId="${spec["categoryId"]}" → "${expectedId}"`);
        }
        const canonicalEmotion = CATEGORY_HINTS[expectedId];
        return {
          ...spec,
          categoryId: expectedId,
          // 已知類別一律用 CATEGORY_HINTS；未知類別（自訂）才保留 Gemini 輸出
          ...(canonicalEmotion !== undefined ? {emotion: canonicalEmotion} : {}),
        };
      });

    if (enhancePersonFeatures) {
      // 人物特徵強化模式：解析 {"specs":[...],"personFeatures":"..."}
      const objMatch = text.match(/\{[\s\S]*\}/);
      if (!objMatch) {
        throw new HttpsError("internal", "Invalid Gemini response format (expected object).");
      }
      let parsed: {specs?: unknown[]; personFeatures?: string};
      try {
        parsed = JSON.parse(objMatch[0]) as {specs?: unknown[]; personFeatures?: string};
      } catch {
        throw new HttpsError("internal", "Failed to parse Gemini response JSON (object).");
      }
      const specsArr = Array.isArray(parsed.specs) ? parsed.specs : [];
      if (specsArr.length < ids.length) {
        throw new HttpsError(
          "internal",
          `Gemini returned ${specsArr.length} specs, expected ${ids.length}.`
        );
      }
      return {
        specs: normalizeSpecs(specsArr),
        personFeatures: parsed.personFeatures ?? null,
      };
    } else {
      const match = text.match(/\[[\s\S]*\]/);
      if (!match) {
        throw new HttpsError("internal", "Invalid Gemini response format.");
      }
      let specs: unknown[];
      try {
        specs = JSON.parse(match[0]) as unknown[];
      } catch {
        throw new HttpsError("internal", "Failed to parse Gemini response JSON (array).");
      }
      if (!Array.isArray(specs) || specs.length < ids.length) {
        throw new HttpsError(
          "internal",
          `Gemini returned ${specs.length} specs, expected ${ids.length}.`
        );
      }
      return {specs: normalizeSpecs(specs)};
    }
  }
);

// ── Sticker Prompt Builder（Server-Side）─────────────────────────────────────
//
// 12 種風格的角色描述與結尾風格語句。
// 索引對應 Flutter StickerStyle enum 順序：
//   0:chibi 1:popArt 2:pixel 3:sketch 4:watercolor 5:webtoon
//   6:celshade 7:pixar3d 8:plush 9:yuruDoodle 10:showaManga 11:claymation

const STYLE_CHAR_DESC: string[] = [
  // 0 chibi
  "根據照片人物繪製卡通 Q 版臉型（可愛 Chibi 風格）\n" +
    "  * 大閃亮眼睛、小鼻子、圓潤臉頰\n" +
    "  * 乾淨平面插畫、粗黑色描邊、非寫實風格\n" +
    "  * 臉部與上半身自然填滿圓形",
  // 1 popArt
  "根據照片人物繪製普普藝術風格的完整 Q 版卡通人物（非肖像、非半身，頭頂至腳底完整呈現）\n" +
    "  * 大膽簡化的臉部特徵、鮮豔高對比色彩\n" +
    "  * 平塗色塊、Ben-Day 網點陰影、無黑色描邊\n" +
    "  * Andy Warhol / Roy Lichtenstein 美術風格\n" +
    "  * 完整身形不被任何畫布邊緣截斷",
  // 2 pixel
  "根據照片人物繪製像素藝術角色\n" +
    "  * 整張圖以 32×32 格子構成再放大，每格至少 4px，強制可見方塊感\n" +
    "  * 限制色盤（≤16 色）、無任何反鋸齒或漸層\n" +
    "  * 所有邊緣皆為直角硬邊；任天堂 / SNES 遊戲像素風",
  // 3 sketch
  "根據照片人物繪製鉛筆素描風格的完整 Q 版卡通人物（非肖像、非半身，頭頂至腳底完整呈現）\n" +
    "  * 手繪線條捕捉照片人物神韻\n" +
    "  * 交叉線條表現深度與陰影、粗糙有力的筆觸\n" +
    "  * 單色或深褐色調\n" +
    "  * 完整身形不被任何畫布邊緣截斷",
  // 4 watercolor
  "根據照片人物繪製水彩風格的完整 Q 版卡通人物（非肖像、非半身，頭頂至腳底完整呈現）\n" +
    "  * 柔和圓潤的臉部、邊緣暈染的溫柔色調\n" +
    "  * 透明疊色、隱約可見的紙張紋理\n" +
    "  * 夢幻可愛的水彩質感\n" +
    "  * 完整身形不被任何畫布邊緣截斷",
  // 5 webtoon
  "根據照片人物繪製韓式 Webtoon 扁平插畫\n" +
    "  * 乾淨圓滑的黑色輪廓線、均勻平塗色彩\n" +
    "  * 明亮柔和的大眼睛、Q 版可愛比例\n" +
    "  * 接近 LINE Friends / NAVER Webtoon 的插畫風格",
  // 6 celshade
  "根據照片人物繪製日系動漫賽璐璐厚塗插畫\n" +
    "  * 清晰的厚黑邊輪廓線、硬邊陰影分層（2–3 階，無漸層邊緣）\n" +
    "  * 飽和鮮豔色彩、強烈光澤反光點\n" +
    "  * 日本動漫賽璐璐作畫風格",
  // 7 pixar3d
  "根據照片人物繪製 Pixar / Disney 3D 渲染風格角色\n" +
    "  * 精緻的 subsurface scattering 膚色、圓潤卡通比例\n" +
    "  * 柔和的環境光遮蔽（AO）、明亮的鏡面高光點\n" +
    "  * Pixar 動畫電影的 3D 渲染質感",
  // 8 plush
  "根據照片人物繪製毛絨布偶玩具風格角色（2D 插畫貼圖，非照片）\n" +
    "  * 模擬短絨毛質感（細小筆觸表現毛流）\n" +
    "  * 圓胖可愛比例、柔和邊緣輪廓\n" +
    "  * 豐富的深淺毛色層次，外觀質感像手工布偶\n" +
    "  * 角色為 2D 平面插圖，無任何攝影背景、地板、環境陰影或真實場景元素",
  // 9 yuruDoodle
  "根據照片人物繪製「ゆるい（鬆散可愛）」塗鴉風格的完整 Q 版角色（頭頂至腳底完整呈現）\n" +
    "  * 刻意歪扭的不均勻輪廓線、五官大小不對稱（一大一小的眼睛等）\n" +
    "  * 粗糙肥厚的黑色手繪線條、面部簡化但身體四肢完整可見\n" +
    "  * 整體散漫自然、像小孩亂畫卻帶有獨特個性與溫度\n" +
    "  * 完整身形（含動態姿勢中舉起的手臂、手掌末端）不被任何畫布邊緣截斷",
  // 10 showaManga
  "根據照片人物繪製昭和復古漫畫風格的完整 Q 版卡通人物（非肖像、非半身，頭頂至腳底完整呈現）\n" +
    "  * 黑白為主（可有限度使用 1–2 種強調色）、手繪網點（スクリーントーン）陰影\n" +
    "  * 粗獷有力的黑色輪廓線、誇張的速度線與動感線條僅集中於角色周邊，不延伸至畫布邊緣\n" +
    "  * 大而明亮的 60 年代漫畫風眼睛、誇張表情框線\n" +
    "  * 完整身形不被任何畫布邊緣截斷",
  // 11 claymation
  "根據照片人物繪製黏土捏塑風格的完整 Q 版角色（2D 插畫貼圖，非照片，頭頂至腳底完整呈現）\n" +
    "  * 模擬手工黏土材質——可見輕微指痕、不均勻的表面起伏\n" +
    "  * 圓潤厚重的造型比例、柔和的邊緣與輪廓\n" +
    "  * 豐富的黏土色澤高光與陰影，外觀像手工捏製的玩偶\n" +
    "  * 角色為 2D 平面插圖，無任何攝影背景、地板或真實場景元素\n" +
    "  * 完整身形不被任何畫布邊緣截斷",
];

const STYLE_PROMPT_SUFFIX: string[] = [
  "LINE Friends / Chiikawa 畫質水準。", // 0 chibi
  "普普藝術風格——鮮豔平塗色彩、Ben-Day 網點陰影、無漸層、無黑色描邊。Andy Warhol / Roy Lichtenstein 美術風格。", // 1 popArt
  "復古 8-bit 像素風格——整張圖如同在 32×32 畫布上繪製再放大 8 倍，每個像素必須明顯呈現方塊感、限制色盤（≤16 色）、絕對無反鋸齒或漸層、所有邊緣皆為直角方塊。任天堂 / SNES 像素風。", // 2 pixel
  "鉛筆素描／手繪風格——單色或深褐色調、可見的鉛筆筆觸與交叉線條陰影、粗糙且富有表現力的線條品質。", // 3 sketch
  "柔和水彩風格——邊緣暈染的溫柔色塊、透明疊色、隱約紙張紋理。可愛夢幻的水彩質感。", // 4 watercolor
  "韓系 Webtoon 插畫風格——乾淨流暢線條、均勻平塗、明亮眼睛。LINE Friends / NAVER Webtoon 畫質水準。", // 5 webtoon
  "日系動漫賽璐璐風格——粗黑輪廓線、硬邊分層陰影（無漸層邊緣）、飽和鮮豔色彩、明顯的高光反光點。", // 6 celshade
  "Pixar 3D 動畫風格——圓潤立體卡通造型、精緻打光（主光源＋補光）、subsurface 膚色、鏡面高光。3D 渲染質感。", // 7 pixar3d
  "毛絨玩偶插畫風格——以 2D 插圖形式模擬短絨毛材質、圓胖可愛比例、柔和邊緣輪廓、豐富毛色深淺層次。角色為純 2D 插圖貼圖，無攝影背景、無地面倒影、無環境投影，角色本體以外區域維持純技術背景色。", // 8 plush
  "日本「下手上手（heta-uma）」ゆるキャラ 風格——刻意不精緻的歪扭線條與不對稱五官，散漫卻充滿個性，像地方吉祥物的手繪質感。", // 9 yuruDoodle
  "昭和復古漫畫風格——黑白手繪、スクリーントーン 網點陰影、粗獷輪廓線、60 年代日本漫畫質感。手塚治虫 / 藤子不二雄 風格。", // 10 showaManga
  "黏土捏塑插畫風格——以 2D 插圖形式模擬手工黏土材質、圓潤厚重比例、可見指痕與不均勻表面起伏。Aardman（笑笑羊）/ 定格動畫黏土玩偶風格。", // 11 claymation
];

interface PromptParams {
  styleIndex: number;
  shape: "circle" | "square";
  specEmotion: string;
  specBgColor: string;
  chromaKey: boolean;
  customStyleDesc?: string;
  customEmotionDesc?: string;
  personFeatures?: string;
}

/** Pro 自訂描述注入段落（與 Flutter 端 _buildProSection 邏輯一致） */
function buildProSection(
  customStyleDesc?: string,
  customEmotionDesc?: string,
  personFeatures?: string,
): string {
  const hints: string[] = [];
  if (customStyleDesc?.trim()) {
    hints.push(
      `🎨 視覺風格（取代預設視覺風格，但構圖邊界留白規則絕對不可變動）：「${customStyleDesc.trim()}」`
    );
  }
  if (customEmotionDesc?.trim()) {
    hints.push(
      `🎭 情緒氛圍（最高優先，貫穿整張貼圖）：「${customEmotionDesc.trim()}」`
    );
  }

  let featureSection = "";
  if (personFeatures?.trim()) {
    featureSection =
      "\n【構圖絕對規則 — 最先執行，任何指令不得覆蓋】\n" +
      "• 角色全身必須完整顯示於畫布內，不得有任何部位超出邊緣\n" +
      "• 頭頂（含髮型、髮飾、帽子、裝飾物）距上緣保留 ≥ 20% 空白（最高優先，速度線等效果不得壓縮此空間）\n" +
      "• 腳底距下緣保留 ≥ 12% 空白\n" +
      "• 左右兩側各保留 ≥ 10% 空白\n" +
      "• 違反以上規則視為生成失敗，請重新構圖\n" +
      "\n【✨ 眼神特徵強化】\n" +
      "請在 Q 版設計中，將以下眼部特徵以誇張手法放大呈現，讓眼神成為角色最鮮明的辨識點：\n" +
      `${personFeatures.trim()}\n` +
      "重點：眼睛形狀、眼神表情、眼部細節（如眼距、眼皮、眼珠大小）需誇大強調。\n" +
      "其他五官與體型依 Q 版比例自然呈現即可，不需過度強調。\n";
  }

  if (!hints.length && !featureSection) return "";
  const proHints = hints.length
    ? `\n【✨ Pro 使用者指定（最高優先級，務必遵循）】\n${hints.join("\n")}\n`
    : "";
  return proHints + featureSection;
}

/** 根據 metadata 組出完整 Gemini prompt（與 Flutter 端 _buildSinglePrompt 邏輯一致） */
function buildPrompt(p: PromptParams): string {
  const idx = Math.max(0, Math.min(p.styleIndex, STYLE_CHAR_DESC.length - 1));
  const hasCustomStyle = !!p.customStyleDesc?.trim();
  const hasCustomEmotion = !!p.customEmotionDesc?.trim();

  const artStyleOpening = hasCustomStyle
    ? `繪製${p.customStyleDesc!.trim()}風格人物`
    : "繪製可愛 Q 版卡通人物";
  const emotionLine = hasCustomEmotion
    ? p.customEmotionDesc!.trim()
    : p.specEmotion;
  const characterDescLine = hasCustomStyle
    ? `以${p.customStyleDesc!.trim()}風格呈現角色，頭頂（含髮型）至腳底完整呈現；角色高度 ≤ 畫布 60%，頭頂距上緣 ≥ 20% 空白，此留白規則適用於所有風格，不可忽略`
    : STYLE_CHAR_DESC[idx];
  const styleSuffix = hasCustomStyle
    ? `${p.customStyleDesc!.trim()}風格，請忽略上方預設風格描述，以此為準。`
    : STYLE_PROMPT_SUFFIX[idx];
  const proSection = buildProSection(
    p.customStyleDesc, p.customEmotionDesc, p.personFeatures
  );

  const commonCharSection =
    `⚠️【構圖規則 — 最高優先，任何風格設定均服從此規則】\n` +
    `角色比例：嬌小插圖風格，參考「角落生物（Sumikkogurashi）」LINE 貼圖的構圖比例——\n` +
    `  角色尺寸明顯小於畫布，四周環繞充裕空白，角色如小插圖漂浮在畫面中。\n` +
    `空間規則：\n` +
    `  · 角色（含動態姿勢最高點，如舉起的手掌末端）距畫布上緣的距離，必須大於角色頭頂到腳底總高度的一半\n` +
    `  · 角色（含動態姿勢最高點）距畫布上緣的距離，必須明顯大於角色自身高度\n` +
    `  · 角色腳底距畫布下緣留有明顯空白，不緊貼邊緣\n` +
    `  · 嚴禁任何部位（頭頂、手掌末端、腳底）被畫布邊緣截斷或觸碰邊緣\n` +
    `動作姿勢指引：若表情動作涉及舉手揮手，採手肘以下的輕鬆揮動（手臂保持在肩膀高度附近），勿雙臂完全高舉過頭\n` +
    `- 根據參考照片，${artStyleOpening}\n` +
    `- 表情 / 動作：${emotionLine}\n` +
    `${proSection}- ${characterDescLine}\n` +
    `- 【禁止文字】畫面任何位置禁止出現任何文字、中文字、英文字母、數字、符號、Logo 或品牌名稱；若參考照片的服裝或配件上有文字圖案，請以純色或簡單幾何紋樣取代，切勿照實重現`;

  if (p.shape === "circle") {
    if (p.chromaKey) {
      return `你是一位專業的 LINE 貼圖插畫師。請根據參考照片，繪製一張正方形貼圖。

【畫布規格 — Chroma Key 去背模式】
背景是純技術用遮罩色，與插畫風格完全無關，必須嚴格遵守以下規則：
- 所有背景區域（角色與裝飾以外的全部畫面）一律以電腦純色平塗填充為純白色 #FFFFFF（R=255, G=255, B=255）
- 背景禁止任何藝術加工：無光暈、無漸層、無反光、無筆觸、無紋理、無陰影投射、無霧感
- 角色或裝飾的陰影禁止落在背景上
- 四個角落像素必須為精確的 #FFFFFF

【角色設計】
${commonCharSection}

【裝飾】在角色周圍點綴 2–4 個小閃光或星星（集中在角色周邊，不接觸背景邊緣）
【輸出】單一正方形 PNG，背景為純平塗 #FFFFFF，無任何光影處理。
風格：${styleSuffix}
`;
    } else {
      return `你是一位專業的 LINE 貼圖插畫師。請根據參考照片，繪製一張正方形貼圖。

【畫布規格】
- 整個正方形畫布以 ${p.specBgColor} 填色作為背景（含四個角落，不得有透明像素）
- 禁止出現任何透明區域、白色邊框或描邊

【角色設計】
${commonCharSection}

【裝飾】在角色周圍點綴 2–4 個小閃光或星星（集中在畫布中央區域）

【配色】背景色：${p.specBgColor}
【輸出】單一正方形 PNG，背景完全不透明。
風格：${styleSuffix}
`;
    }
  } else {
    if (p.chromaKey) {
      return `你是一位專業的 LINE 貼圖插畫師。請根據參考照片，繪製一張方形貼圖。

【畫布規格 — Chroma Key 去背模式】
背景是純技術用遮罩色，與插畫風格完全無關，必須嚴格遵守以下規則：
- 所有背景區域（角色與裝飾以外的全部畫面）一律以電腦純色平塗填充為純白色 #FFFFFF（R=255, G=255, B=255）
- 背景禁止任何藝術加工：無光暈、無漸層、無反光、無筆觸、無紋理、無陰影投射、無霧感
- 角色或裝飾的陰影禁止落在背景上
- 四個角落像素必須為精確的 #FFFFFF

【角色設計】
${commonCharSection}
- 角色周圍點綴 3–5 個小閃光或星星（集中在角色周邊，不接觸背景邊緣）
【輸出】單一正方形 PNG，背景為純平塗 #FFFFFF，無任何光影處理。
風格：${styleSuffix}
`;
    } else {
      return `你是一位專業的 LINE 貼圖插畫師。請根據參考照片，繪製一張方形貼圖。

【設計規格】
- 整個正方形畫布以 ${p.specBgColor} 填色作為背景
- 角色表情 / 動作：${emotionLine}
${proSection}- ${characterDescLine}
${commonCharSection}
- 背景中點綴 3–5 個小閃光或星星
- 禁止出現任何白色邊框或白色描邊
【輸出】單一正方形 PNG，無白色背景。
風格：${styleSuffix}
`;
    }
  }
}

// ── generateStickerImage ────────────────────────────────────────────────────
//
// 1. 驗證 Firebase Auth
// 2. Firestore Transaction 原子性扣 1 點 + 寫 creditHistory
// 3. proxy Gemini Image API
// 4. 失敗時退還 1 點 + 寫退點紀錄

export const generateStickerImage = onCall(
  {
    region: "asia-east1",
    timeoutSeconds: 120,
    memory: "1GiB",
    secrets: [geminiApiKey],
    invoker: "public",
    enforceAppCheck: false,
  },
  async (request) => {
    // ★ 此行出現在 Firebase Logs = Cloud Run IAM 通過，function 程式碼有執行
    log("generateStickerImage: invoked", {
      hasAuth: !!request.auth,
      hasAuthHeader: !!request.rawRequest?.headers?.authorization,
      hasAppCheck: !!request.app,
    });
    if (!request.app) {
      warn("generateStickerImage: App Check token missing (App Distribution build?)");
    }
    const uid = await resolveUid(request);
    log("generateStickerImage: auth OK", {uid});

    // 雙協議相容：
    //   舊協議（App < v3.18.29）：傳 { photoBase64, prompt } → 直接使用
    //   新協議（App ≥ v3.18.29）：傳 metadata → CF 自行組 prompt
    const data = request.data as {
      photoBase64: string;
      prompt?: string;           // 舊協議
      styleIndex?: number;       // 新協議
      shape?: string;
      specEmotion?: string;
      specBgColor?: string;
      chromaKey?: boolean;
      customStyleDesc?: string;
      customEmotionDesc?: string;
      personFeatures?: string;
    };

    const {photoBase64} = data;
    if (!photoBase64) {
      throw new HttpsError("invalid-argument", "photoBase64 is required.");
    }

    let finalPrompt: string;
    if (data.prompt) {
      // 舊協議：Flutter 端已組好 prompt，直接使用（向下相容）
      finalPrompt = data.prompt;
    } else if (data.styleIndex !== undefined && data.specEmotion) {
      // 新協議：CF 從 metadata 組 prompt
      finalPrompt = buildPrompt({
        styleIndex: data.styleIndex,
        shape: (data.shape ?? "square") as "circle" | "square",
        specEmotion: data.specEmotion,
        specBgColor: data.specBgColor ?? "",
        chromaKey: data.chromaKey ?? true,
        customStyleDesc: data.customStyleDesc,
        customEmotionDesc: data.customEmotionDesc,
        personFeatures: data.personFeatures,
      });
    } else {
      throw new HttpsError(
        "invalid-argument",
        "Either 'prompt' (legacy) or 'styleIndex + specEmotion' (v2) is required."
      );
    }

    // ── 原子性扣點 + 寫 creditHistory ────────────────────────────────────────
    const userRef = db.collection("users").doc(uid);
    let remainingCredits = 0;

    const deducted = await db.runTransaction(async (tx) => {
      const doc = await tx.get(userRef);
      const credits = (doc.data()?.credits as number) ?? 0;
      if (credits <= 0) return false;
      remainingCredits = credits - 1;
      tx.update(userRef, {
        credits: remainingCredits,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      writeCreditHistory(tx, uid, {
        type: "spent",
        amount: -1,
        reason: "generate_sticker_image",
      });
      return true;
    });

    if (!deducted) {
      throw new HttpsError("resource-exhausted", "Insufficient credits.");
    }

    // ── 記錄實際送出的 prompt（方便 debug 截圖截頭等構圖問題）────────────────
    log("generateStickerImage: prompt_sent", {uid, protocol: data.prompt ? "legacy" : "v2", prompt: finalPrompt});

    // ── 呼叫 Gemini Image API ────────────────────────────────────────────────
    const apiKey = geminiApiKey.value();
    const imgModel = geminiImageModel.value();
    const endpoint =
      "https://generativelanguage.googleapis.com/v1beta" +
      `/models/${imgModel}:generateContent?key=${apiKey}`;

    const body = {
      contents: [
        {
          parts: [
            {text: finalPrompt},
            {
              inlineData: {
                mimeType: "image/jpeg",
                data: photoBase64,
              },
            },
          ],
        },
      ],
      generationConfig: {
        responseModalities: ["IMAGE", "TEXT"],
      },
    };

    // ── try/catch 包覆所有 Gemini 呼叫，確保任何意外例外（AbortError、JSON 解析錯誤等）
    // 都能退還已扣的點數。HttpsError 表示內部已自行處理退款，直接重拋。
    try {
      const res = await fetch(endpoint, {
        method: "POST",
        headers: {"Content-Type": "application/json"},
        body: JSON.stringify(body),
        signal: AbortSignal.timeout(110000),
      });

      if (res.status === 429) {
        // 退還點數
        await db.runTransaction(async (tx) => {
          tx.update(userRef, {
            credits: admin.firestore.FieldValue.increment(1),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          writeCreditHistory(tx, uid, {
            type: "refund",
            amount: 1,
            reason: "rate_limited",
          });
        });
        const retryAfter = res.headers.get("Retry-After") ?? "30";
        throw new HttpsError(
          "resource-exhausted",
          `Rate limited. Retry after ${retryAfter}s.`
        );
      }

      if (!res.ok) {
        const errText = await res.text();
        // 退還點數
        await db.runTransaction(async (tx) => {
          tx.update(userRef, {
            credits: admin.firestore.FieldValue.increment(1),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          writeCreditHistory(tx, uid, {
            type: "refund",
            amount: 1,
            reason: "api_error",
          });
        });
        throw new HttpsError(
          "internal",
          `Gemini image API error ${res.status}: ${errText.slice(0, 300)}`
        );
      }

      const json = (await res.json()) as {
        candidates?: Array<{
          content: {
            parts: Array<{
              inlineData?: {mimeType: string; data: string};
            }>;
          };
          finishReason?: string;
        }>;
        promptFeedback?: {blockReason?: string};
      };

      // 檢查 Gemini 是否封鎖此請求（版權/安全審查）
      const imgBlockReason = json.promptFeedback?.blockReason
        ?? json.candidates?.[0]?.finishReason;
      const isBlocked = !json.candidates?.length
        || imgBlockReason === "SAFETY"
        || imgBlockReason === "OTHER"
        || imgBlockReason === "PROHIBITED_CONTENT"
        || imgBlockReason === "COPYRIGHT";

      const parts = isBlocked ? [] : (json.candidates?.[0]?.content?.parts ?? []);
      for (const part of parts) {
        if (part.inlineData?.mimeType?.startsWith("image/")) {
          return {imageBase64: part.inlineData.data, remainingCredits};
        }
      }

      // 沒拿到圖片 → 退點
      await db.runTransaction(async (tx) => {
        tx.update(userRef, {
          credits: admin.firestore.FieldValue.increment(1),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        writeCreditHistory(tx, uid, {
          type: "refund",
          amount: 1,
          reason: isBlocked ? "content_blocked" : "no_image_returned",
        });
      });
      if (isBlocked) {
        throw new HttpsError(
          "invalid-argument",
          `Gemini blocked the image request (reason: ${imgBlockReason ?? "no candidates"}). ` +
          "Please avoid copyrighted brand names or sensitive terms."
        );
      }
      throw new HttpsError("internal", "No image returned by Gemini.");
    } catch (e) {
      // HttpsError = 內部已自行處理退款邏輯（429、!ok、blocked、no image），直接重拋
      if (e instanceof HttpsError) throw e;
      // 意外例外（AbortError/逾時、JSON 解析失敗、網路錯誤等）→ 退還已扣的點數
      warn("generateStickerImage: unexpected error after credit deduction, refunding", {
        uid,
        error: String(e),
      });
      try {
        await db.runTransaction(async (tx) => {
          tx.update(userRef, {
            credits: admin.firestore.FieldValue.increment(1),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          writeCreditHistory(tx, uid, {
            type: "refund",
            amount: 1,
            reason: "unexpected_error",
          });
        });
        log("generateStickerImage: credit refunded for unexpected error", {uid});
      } catch (refundErr) {
        warn("generateStickerImage: failed to refund credit after unexpected error", {
          uid,
          error: String(refundErr),
        });
      }
      throw new HttpsError("internal", "生成失敗，點數已退還。請稍後重試。");
    }
  }
);

// ── checkTopEdgeCut ──────────────────────────────────────────────────────────

/**
 * 偵測 PNG 圖片頂部是否有角色像素（非白色），判斷角色是否被畫布上緣截斷。
 *
 * 方法：解析 PNG IHDR 取得寬高，用 inflateSync 解壓 IDAT chunk，
 * 還原各行 PNG filter，掃描頂部 pct（預設 8%）的行。
 * 若任一行出現非白色像素（RGB < 250），代表角色頂部被截斷。
 *
 * 支援 8-bit RGB（colorType=2）與 RGBA（colorType=6）PNG；
 * 其他格式一律回傳 false（不觸發 retry）。
 */
function checkTopEdgeCut(imageBase64: string, pct = 0.08): boolean {
  try {
    const buf = Buffer.from(imageBase64, "base64");

    // PNG 簽名驗證（89 50 4E 47 0D 0A 1A 0A）
    if (buf.length < 33) return false;
    if (
      buf[0] !== 0x89 || buf[1] !== 0x50 ||
      buf[2] !== 0x4e || buf[3] !== 0x47
    ) return false;

    // IHDR chunk（固定在 offset 8，chunk data 從 offset 16 開始）
    if (buf.toString("ascii", 12, 16) !== "IHDR") return false;

    const width     = buf.readUInt32BE(16);
    const height    = buf.readUInt32BE(20);
    const bitDepth  = buf.readUInt8(24);
    const colorType = buf.readUInt8(25);

    // 只支援 8-bit RGB(2) 或 RGBA(6)
    if (bitDepth !== 8 || (colorType !== 2 && colorType !== 6)) return false;
    const channels = colorType === 6 ? 4 : 3;

    // 收集所有 IDAT chunk 資料
    const idatChunks: Buffer[] = [];
    let offset = 8;
    while (offset + 12 <= buf.length) {
      const chunkLen  = buf.readUInt32BE(offset);
      const chunkType = buf.toString("ascii", offset + 4, offset + 8);
      if (chunkType === "IDAT") {
        idatChunks.push(buf.subarray(offset + 8, offset + 8 + chunkLen));
      } else if (chunkType === "IEND") {
        break;
      }
      offset += 12 + chunkLen;
    }
    if (idatChunks.length === 0) return false;

    // 解壓縮 zlib/deflate IDAT 資料
    const raw       = inflateSync(Buffer.concat(idatChunks));
    const checkRows = Math.max(1, Math.floor(height * pct));
    const stride    = 1 + width * channels; // 1 filter byte + pixel data per row

    let prevRow = Buffer.alloc(width * channels, 0xff); // 上一行初始全白

    for (let row = 0; row < checkRows; row++) {
      const base = row * stride;
      if (base + stride > raw.length) return false;

      const filterType = raw[base];
      const recon      = Buffer.allocUnsafe(width * channels);

      // 還原 PNG filter（5 種類型：None/Sub/Up/Average/Paeth）
      for (let i = 0; i < width * channels; i++) {
        const x = raw[base + 1 + i];
        const a = i >= channels ? recon[i - channels]   : 0; // left
        const b = prevRow[i];                                 // above
        const c = i >= channels ? prevRow[i - channels] : 0; // upper-left

        let val: number;
        switch (filterType) {
          case 0: val = x; break;
          case 1: val = (x + a) & 0xff; break;
          case 2: val = (x + b) & 0xff; break;
          case 3: val = (x + ((a + b) >>> 1)) & 0xff; break;
          case 4: {
            const p  = a + b - c;
            const pa = Math.abs(p - a);
            const pb = Math.abs(p - b);
            const pc = Math.abs(p - c);
            val = (x + (pa <= pb && pa <= pc ? a : pb <= pc ? b : c)) & 0xff;
            break;
          }
          default: val = x;
        }
        recon[i] = val;
      }

      // 掃描這行：任一像素 RGB < 250 → 非白色 → 角色被截斷
      for (let px = 0; px < width; px++) {
        const p = px * channels;
        if (recon[p] < 250 || recon[p + 1] < 250 || recon[p + 2] < 250) {
          return true;
        }
      }

      prevRow = recon;
    }
    return false;
  } catch {
    return false; // 解析失敗，不觸發 retry
  }
}

// ── generateStickerImageV2 ───────────────────────────────────────────────────
//
// 版本化入口（v2）：僅接受新協議（App ≥ v3.18.30），不支援舊版 prompt 字串。
// 舊版 App 繼續使用 generateStickerImage (V1)，兩者互不影響。
//
// 1. 驗證 Firebase Auth
// 2. Firestore Transaction 原子性扣 1 點 + 寫 creditHistory
// 3. 由 metadata 組 prompt → proxy Gemini Image API
// 4. 失敗時退還 1 點 + 寫退點紀錄

export const generateStickerImageV2 = onCall(
  {
    region: "asia-east1",
    timeoutSeconds: 200,
    memory: "1GiB",
    secrets: [geminiApiKey],
    invoker: "public",
    enforceAppCheck: false,
  },
  async (request) => {
    log("generateStickerImageV2: invoked", {
      hasAuth: !!request.auth,
      hasAuthHeader: !!request.rawRequest?.headers?.authorization,
      hasAppCheck: !!request.app,
    });
    if (!request.app) {
      warn("generateStickerImageV2: App Check token missing (App Distribution build?)");
    }
    const uid = await resolveUid(request);
    log("generateStickerImageV2: auth OK", {uid});

    const data = request.data as {
      photoBase64: string;
      styleIndex: number;
      shape?: string;
      specEmotion: string;
      specBgColor?: string;
      chromaKey?: boolean;
      customStyleDesc?: string;
      customEmotionDesc?: string;
      personFeatures?: string;
    };

    const {photoBase64} = data;
    if (!photoBase64) {
      throw new HttpsError("invalid-argument", "photoBase64 is required.");
    }
    if (data.styleIndex === undefined || !data.specEmotion) {
      throw new HttpsError(
        "invalid-argument",
        "'styleIndex' and 'specEmotion' are required. Please update the app."
      );
    }

    const finalPrompt = buildPrompt({
      styleIndex: data.styleIndex,
      shape: (data.shape ?? "square") as "circle" | "square",
      specEmotion: data.specEmotion,
      specBgColor: data.specBgColor ?? "",
      chromaKey: data.chromaKey ?? true,
      customStyleDesc: data.customStyleDesc,
      customEmotionDesc: data.customEmotionDesc,
      personFeatures: data.personFeatures,
    });

    // ── 原子性扣點 + 寫 creditHistory ────────────────────────────────────────
    const userRef = db.collection("users").doc(uid);
    let remainingCredits = 0;

    const deducted = await db.runTransaction(async (tx) => {
      const doc = await tx.get(userRef);
      const credits = (doc.data()?.credits as number) ?? 0;
      if (credits <= 0) return false;
      remainingCredits = credits - 1;
      tx.update(userRef, {
        credits: remainingCredits,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      writeCreditHistory(tx, uid, {
        type: "spent",
        amount: -1,
        reason: "generate_sticker_image_v2",
      });
      return true;
    });

    if (!deducted) {
      throw new HttpsError("resource-exhausted", "Insufficient credits.");
    }

    log("generateStickerImageV2: prompt_sent", {uid, prompt: finalPrompt});

    // ── 呼叫 Gemini Image API ────────────────────────────────────────────────
    const apiKey = geminiApiKey.value();
    const imgModel = geminiImageModel.value();
    const endpoint =
      "https://generativelanguage.googleapis.com/v1beta" +
      `/models/${imgModel}:generateContent?key=${apiKey}`;

    const body = {
      contents: [
        {
          parts: [
            {text: finalPrompt},
            {
              inlineData: {
                mimeType: "image/jpeg",
                data: photoBase64,
              },
            },
          ],
        },
      ],
      generationConfig: {
        responseModalities: ["IMAGE", "TEXT"],
      },
    };

    try {
      const res = await fetch(endpoint, {
        method: "POST",
        headers: {"Content-Type": "application/json"},
        body: JSON.stringify(body),
        signal: AbortSignal.timeout(90000),
      });

      if (res.status === 429) {
        await db.runTransaction(async (tx) => {
          tx.update(userRef, {
            credits: admin.firestore.FieldValue.increment(1),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          writeCreditHistory(tx, uid, {
            type: "refund",
            amount: 1,
            reason: "rate_limited",
          });
        });
        const retryAfter = res.headers.get("Retry-After") ?? "30";
        throw new HttpsError(
          "resource-exhausted",
          `Rate limited. Retry after ${retryAfter}s.`
        );
      }

      if (!res.ok) {
        const errText = await res.text();
        await db.runTransaction(async (tx) => {
          tx.update(userRef, {
            credits: admin.firestore.FieldValue.increment(1),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          writeCreditHistory(tx, uid, {
            type: "refund",
            amount: 1,
            reason: "api_error",
          });
        });
        throw new HttpsError(
          "internal",
          `Gemini image API error ${res.status}: ${errText.slice(0, 300)}`
        );
      }

      const json = (await res.json()) as {
        candidates?: Array<{
          content: {
            parts: Array<{
              inlineData?: {mimeType: string; data: string};
            }>;
          };
          finishReason?: string;
        }>;
        promptFeedback?: {blockReason?: string};
      };

      const imgBlockReason = json.promptFeedback?.blockReason
        ?? json.candidates?.[0]?.finishReason;
      const isBlocked = !json.candidates?.length
        || imgBlockReason === "SAFETY"
        || imgBlockReason === "OTHER"
        || imgBlockReason === "PROHIBITED_CONTENT"
        || imgBlockReason === "COPYRIGHT";

      const parts = isBlocked ? [] : (json.candidates?.[0]?.content?.parts ?? []);
      for (const part of parts) {
        if (part.inlineData?.mimeType?.startsWith("image/")) {
          const firstImg = part.inlineData.data;

          // ── 頂部截斷自動偵測 & 一次 retry ──────────────────────────────
          if (checkTopEdgeCut(firstImg)) {
            log("generateStickerImageV2: top-edge cut detected, retrying with size correction", {uid});
            const retryPrompt = finalPrompt +
              "\n\n⚠️ 前次生成的角色太大，頭頂超出畫布上緣被截斷。" +
              "此次必須大幅縮小角色：角色（含動態姿勢最高點）" +
              "的高度不超過畫布高度的三分之一，四周保留大量空白，不充滿畫面。";
            try {
              const retryRes = await fetch(endpoint, {
                method: "POST",
                headers: {"Content-Type": "application/json"},
                body: JSON.stringify({
                  contents: [{
                    parts: [
                      {text: retryPrompt},
                      {inlineData: {mimeType: "image/jpeg", data: photoBase64}},
                    ],
                  }],
                  generationConfig: {responseModalities: ["IMAGE", "TEXT"]},
                }),
                signal: AbortSignal.timeout(80000),
              });
              if (retryRes.ok) {
                const retryJson = await retryRes.json() as {
                  candidates?: Array<{
                    content: {parts: Array<{inlineData?: {mimeType: string; data: string}}>};
                  }>;
                };
                for (const rp of (retryJson.candidates?.[0]?.content?.parts ?? [])) {
                  if (rp.inlineData?.mimeType?.startsWith("image/")) {
                    log("generateStickerImageV2: size-correction retry succeeded", {uid});
                    return {imageBase64: rp.inlineData.data, remainingCredits};
                  }
                }
              }
            } catch (retryErr) {
              warn("generateStickerImageV2: size-correction retry failed", {uid, error: String(retryErr)});
            }
            // retry 失敗 → 回傳原始圖（有截斷但不退點，使用者仍拿到圖片）
            log("generateStickerImageV2: retry failed, returning original image", {uid});
          }

          return {imageBase64: firstImg, remainingCredits};
        }
      }

      await db.runTransaction(async (tx) => {
        tx.update(userRef, {
          credits: admin.firestore.FieldValue.increment(1),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        writeCreditHistory(tx, uid, {
          type: "refund",
          amount: 1,
          reason: isBlocked ? "content_blocked" : "no_image_returned",
        });
      });
      if (isBlocked) {
        throw new HttpsError(
          "invalid-argument",
          `Gemini blocked the image request (reason: ${imgBlockReason ?? "no candidates"}). ` +
          "Please avoid copyrighted brand names or sensitive terms."
        );
      }
      throw new HttpsError("internal", "No image returned by Gemini.");
    } catch (e) {
      if (e instanceof HttpsError) throw e;
      warn("generateStickerImageV2: unexpected error after credit deduction, refunding", {
        uid,
        error: String(e),
      });
      try {
        await db.runTransaction(async (tx) => {
          tx.update(userRef, {
            credits: admin.firestore.FieldValue.increment(1),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          writeCreditHistory(tx, uid, {
            type: "refund",
            amount: 1,
            reason: "unexpected_error",
          });
        });
        log("generateStickerImageV2: credit refunded for unexpected error", {uid});
      } catch (refundErr) {
        warn("generateStickerImageV2: failed to refund credit after unexpected error", {
          uid,
          error: String(refundErr),
        });
      }
      throw new HttpsError("internal", "生成失敗，點數已退還。請稍後重試。");
    }
  }
);

// ── Play API auth helper ──────────────────────────────────────────────────────

/**
 * 取得 Google Play Developer API 的 OAuth2 Access Token。
 * Cloud Run 以 github-play-store-deployer service account 執行，ADC 自動取得授權。
 */
async function getPlayAccessToken(): Promise<string> {
  const auth = new GoogleAuth({
    scopes: ["https://www.googleapis.com/auth/androidpublisher"],
  });
  const client = await auth.getClient();
  const tokenResponse = await client.getAccessToken();

  // tokenResponse 可能是 string（部分 auth 類型）、GetAccessTokenResponse 或 null
  const token =
    typeof tokenResponse === "string"
      ? tokenResponse
      : tokenResponse?.token ?? null;

  if (!token) {
    warn("getPlayAccessToken: empty token", {
      responseType: typeof tokenResponse,
      responseKeys: tokenResponse && typeof tokenResponse === "object"
        ? Object.keys(tokenResponse)
        : [],
    });
    throw new Error(
      `getAccessToken returned empty token (responseType=${typeof tokenResponse})`
    );
  }
  return token;
}

// ── App Store Server API (v1) helper ──────────────────────────────────────────
//
// 使用 App Store Connect API Key（ES256 JWT）驗證交易。
// Flutter 端傳入 purchase.purchaseID（iOS transaction ID），
// CF 用 GET /inApps/v1/transactions/{transactionId} 查詢交易狀態。
//
// 所需 Firebase Secrets：
//   APP_STORE_KEY_ID      — App Store Connect API Key 的 Key ID（10 字元）
//   APP_STORE_ISSUER_ID   — App Store Connect 的 Issuer ID（UUID）
//   APP_STORE_PRIVATE_KEY — .p8 私鑰內容（PKCS8 PEM 格式）
//
// 流程：先打 Production，HTTP 404 代表 sandbox 交易，自動 retry sandbox endpoint。

const kAppleBundleId = "com.magicsticker.magic-sticker";

interface AppleVerifyResult {
  valid: boolean;
  status: number;
  productId?: string;
  quantity?: number;
  transactionId?: string;
}

interface AppStoreTransactionPayload {
  transactionId: string;
  originalTransactionId: string;
  bundleId: string;
  productId: string;
  quantity: number;
  type: string;
  revocationDate?: number;
  revocationReason?: number;
}

/** 產生 App Store Server API 所需的 ES256 JWT（有效 15 分鐘）。 */
function generateAppStoreJWT(): string {
  const now = Math.floor(Date.now() / 1000);
  const keyId = appStoreKeyId.value();
  const issuerId = appStoreIssuerId.value();
  // Secret Manager 中可能以字面 \n 儲存（GitHub Actions env 注入時常見），
  // 先將字面 \n 轉為真正的換行符，確保 PEM 格式正確。
  const rawPem = appStorePrivateKey.value().replace(/\\n/g, "\n");

  log("generateAppStoreJWT: keyId=" + keyId.slice(0, 4) + "… issuerId=" + issuerId.slice(0, 8) + "…");

  const header = Buffer.from(
    JSON.stringify({alg: "ES256", kid: keyId, typ: "JWT"})
  ).toString("base64url");
  const payload = Buffer.from(
    JSON.stringify({
      iss: issuerId,
      iat: now,
      exp: now + 900,
      aud: "appstoreconnect-v1",
      bid: kAppleBundleId,
    })
  ).toString("base64url");

  const signingInput = `${header}.${payload}`;
  const privateKey = crypto.createPrivateKey(rawPem);
  // IEEE P1363 格式（R||S fixed-length）是 JWS ES256 規範要求的格式
  const sig = crypto.sign("sha256", Buffer.from(signingInput), {
    key: privateKey,
    dsaEncoding: "ieee-p1363",
  });
  return `${signingInput}.${sig.toString("base64url")}`;
}

/**
 * StoreKit 2 のローカル JWS 検証。
 * App Store Server API（要 API Key）を使わず、Apple 署名の JWS を直接検証する。
 *
 * 検証手順：
 * 1. JWS ヘッダーの x5c 証明書チェーンを取得
 * 2. チェーンの連鎖性を確認（各 cert が次の cert で署名）
 * 3. ルート cert が自己署名 + Apple Root CA であることを確認
 * 4. リーフ cert の公開鍵で JWS 署名を検証
 * 5. ペイロードの bundleId / productId / revocation を確認
 */
async function verifyAppleJWSLocal(
  jwsTransaction: string,
  expectedProductId: string
): Promise<AppleVerifyResult> {
  const parts = jwsTransaction.split(".");
  if (parts.length !== 3) {
    warn("verifyAppleJWSLocal: invalid JWS format (expected 3 parts)");
    return {valid: false, status: 0};
  }

  // 1. ヘッダーの x5c を取得
  let header: {alg?: string; x5c?: string[]; typ?: string};
  try {
    header = JSON.parse(Buffer.from(parts[0], "base64url").toString("utf8"));
  } catch (e) {
    warn("verifyAppleJWSLocal: failed to parse JWS header", {error: String(e)});
    return {valid: false, status: 0};
  }

  if (header.alg !== "ES256" || !header.x5c || header.x5c.length < 2) {
    warn("verifyAppleJWSLocal: invalid header fields", {alg: header.alg, x5cLen: header.x5c?.length});
    return {valid: false, status: 0};
  }

  // 2. DER → X509Certificate
  let certs: crypto.X509Certificate[];
  try {
    certs = header.x5c.map((b64) => new crypto.X509Certificate(Buffer.from(b64, "base64")));
  } catch (e) {
    warn("verifyAppleJWSLocal: failed to parse certs", {error: String(e)});
    return {valid: false, status: 0};
  }

  // 3. 証明書チェーン検証（certs[i] は certs[i+1] の公開鍵で署名）
  for (let i = 0; i < certs.length - 1; i++) {
    try {
      if (!certs[i].verify(certs[i + 1].publicKey)) {
        warn("verifyAppleJWSLocal: cert chain broken at index", {i});
        return {valid: false, status: 0};
      }
    } catch (e) {
      warn("verifyAppleJWSLocal: cert chain verify error", {i, error: String(e)});
      return {valid: false, status: 0};
    }
  }

  // 4. ルート cert が自己署名 + Apple Root CA であることを確認
  const rootCert = certs[certs.length - 1];
  try {
    if (!rootCert.verify(rootCert.publicKey)) {
      warn("verifyAppleJWSLocal: root cert is not self-signed");
      return {valid: false, status: 0};
    }
  } catch (e) {
    warn("verifyAppleJWSLocal: root cert self-verify error", {error: String(e)});
    return {valid: false, status: 0};
  }
  if (!rootCert.subject.includes("Apple Root CA")) {
    warn("verifyAppleJWSLocal: root cert subject is not Apple Root CA", {subject: rootCert.subject});
    return {valid: false, status: 0};
  }

  // 5. リーフ cert の公開鍵で JWS 署名を検証（IEEE P1363 形式）
  const signingInput = Buffer.from(`${parts[0]}.${parts[1]}`);
  const signature = Buffer.from(parts[2], "base64url");
  let isSigValid: boolean;
  try {
    isSigValid = crypto.verify(
      "sha256",
      signingInput,
      {key: certs[0].publicKey, dsaEncoding: "ieee-p1363"},
      signature
    );
  } catch (e) {
    warn("verifyAppleJWSLocal: signature verify error", {error: String(e)});
    return {valid: false, status: 0};
  }
  if (!isSigValid) {
    warn("verifyAppleJWSLocal: JWS signature is invalid");
    return {valid: false, status: 0};
  }

  // 6. ペイロードの検証
  let txPayload: AppStoreTransactionPayload;
  try {
    txPayload = JSON.parse(Buffer.from(parts[1], "base64url").toString("utf8"));
  } catch (e) {
    warn("verifyAppleJWSLocal: failed to parse JWS payload", {error: String(e)});
    return {valid: false, status: 0};
  }

  if (txPayload.bundleId !== kAppleBundleId) {
    warn("verifyAppleJWSLocal: bundleId mismatch", {expected: kAppleBundleId, got: txPayload.bundleId});
    return {valid: false, status: 0};
  }
  if (txPayload.productId !== expectedProductId) {
    warn("verifyAppleJWSLocal: productId mismatch", {expected: expectedProductId, got: txPayload.productId});
    return {valid: false, status: 0};
  }
  if (txPayload.revocationDate) {
    warn("verifyAppleJWSLocal: transaction revoked", {transactionId: txPayload.transactionId});
    return {valid: false, status: 0};
  }

  log("verifyAppleJWSLocal: verification OK", {transactionId: txPayload.transactionId, productId: txPayload.productId});
  return {
    valid: true,
    status: 200,
    productId: txPayload.productId,
    quantity: txPayload.quantity ?? 1,
    transactionId: txPayload.transactionId,
  };
}


async function verifyAppleTransaction(
  transactionId: string,
  expectedProductId: string
): Promise<AppleVerifyResult> {
  const jwt = generateAppStoreJWT();

  const tryFetch = (baseUrl: string) =>
    fetch(`${baseUrl}/inApps/v1/transactions/${transactionId}`, {
      headers: {Authorization: `Bearer ${jwt}`},
      signal: AbortSignal.timeout(15000),
    });

  let res = await tryFetch("https://api.storekit.itunes.apple.com");

  // 404 in production = sandbox transaction → retry sandbox endpoint
  if (res.status === 404) {
    log("verifyAppleTransaction: not in production, retrying sandbox");
    res = await tryFetch("https://api.storekit-sandbox.itunes.apple.com");
  }

  if (!res.ok) {
    if (res.status === 401) {
      // 401 = JWT 驗證失敗 → 通常是 Secret Manager 中的 KEY_ID / ISSUER_ID / PRIVATE_KEY 設定錯誤或已撤銷
      warn("verifyAppleTransaction: 401 Unauthorized — check APP_STORE_KEY_ID / APP_STORE_ISSUER_ID / APP_STORE_PRIVATE_KEY secrets");
    } else {
      warn("verifyAppleTransaction: API error", {status: res.status});
    }
    return {valid: false, status: res.status};
  }

  const data = await res.json() as {signedTransactionInfo: string};
  const parts = data.signedTransactionInfo?.split(".");
  if (!parts || parts.length !== 3) {
    warn("verifyAppleTransaction: invalid JWS format");
    return {valid: false, status: 0};
  }

  let txPayload: AppStoreTransactionPayload;
  try {
    txPayload = JSON.parse(
      Buffer.from(parts[1], "base64url").toString("utf8")
    ) as AppStoreTransactionPayload;
  } catch {
    warn("verifyAppleTransaction: failed to parse JWS payload");
    return {valid: false, status: 0};
  }

  if (txPayload.productId !== expectedProductId) {
    warn("verifyAppleTransaction: productId mismatch", {
      expected: expectedProductId,
      got: txPayload.productId,
    });
    return {valid: false, status: 0};
  }

  if (txPayload.revocationDate) {
    warn("verifyAppleTransaction: transaction revoked", {
      transactionId,
      revocationDate: txPayload.revocationDate,
    });
    return {valid: false, status: 0};
  }

  return {
    valid: true,
    status: 200,
    productId: txPayload.productId,
    quantity: txPayload.quantity ?? 1,
    transactionId: txPayload.transactionId,
  };
}

// ── verifyProPurchase ─────────────────────────────────────────────────────────
//
// 1. 驗證 Firebase Auth
// 2. 依 platform 分流：Android → Google Play API；iOS → App Store Server API
// 3. 寫入 Firestore: users/{uid}/purchases/pro_custom_input

const kPackageName = "com.magicsticker.magic_sticker";
const kProProductId = "pro_custom_input";

export const verifyProPurchase = onCall(
  {
    region: "asia-east1",
    timeoutSeconds: 30,
    memory: "256MiB",
    invoker: "public",
    enforceAppCheck: false,
    secrets: [appStoreKeyId, appStoreIssuerId, appStorePrivateKey],
    serviceAccount: "github-play-store-deployer@magic-sticker-8eaf4.iam.gserviceaccount.com",
  },
  async (request) => {
    log("verifyProPurchase: invoked", {
      hasAuth: !!request.auth,
      hasAppCheck: !!request.app,
    });
    const uid = await resolveUid(request);
    log("verifyProPurchase: auth OK", {uid});

    const {purchaseToken, orderId, platform = "android", jwsTransaction} = request.data as {
      purchaseToken: string;
      orderId?: string;
      platform?: string;
      jwsTransaction?: string;
    };

    if (!purchaseToken) {
      throw new HttpsError("invalid-argument", "purchaseToken is required.");
    }

    // ── 冪等性快捷路徑：若同一 purchaseToken 已驗證，直接回傳成功 ────────────
    // 解決 PurchaseStatus.restored 重複觸發導致的無限重試問題
    const existingPurchase = await db
      .collection("users")
      .doc(uid)
      .collection("purchases")
      .doc(kProProductId)
      .get();
    if (existingPurchase.exists) {
      const d = existingPurchase.data();
      if (d?.verified === true && d?.purchase_token === purchaseToken) {
        log("verifyProPurchase: already verified in Firestore, fast-path return", {uid});
        return {success: true};
      }
    }

    if (platform === "ios") {
      // ── iOS：JWS ローカル検証（優先）→ App Store Server API（フォールバック）──
      let appleResult: AppleVerifyResult;

      if (jwsTransaction) {
        // StoreKit 2 の JWS をローカルで検証（API Key 不要）
        try {
          appleResult = await verifyAppleJWSLocal(jwsTransaction, kProProductId);
          log("verifyProPurchase: local JWS verified", {uid, valid: appleResult.valid});
        } catch (e) {
          warn("verifyProPurchase: local JWS failed, falling back to API", {error: String(e)});
          appleResult = {valid: false, status: 0};
        }
        // JWS 検証失敗時は App Store Server API にフォールバック
        if (!appleResult.valid) {
          try {
            appleResult = await verifyAppleTransaction(purchaseToken, kProProductId);
            log("verifyProPurchase: fallback API verified", {uid, status: appleResult.status});
          } catch (e) {
            warn("verifyProPurchase: Apple API fallback failed", {error: String(e)});
            throw new HttpsError("unavailable", "Unable to verify Apple purchase. Please try again.");
          }
        }
      } else {
        // JWS なし（旧クライアント互換）→ App Store Server API
        try {
          appleResult = await verifyAppleTransaction(purchaseToken, kProProductId);
          log("verifyProPurchase: Apple API verified", {uid, status: appleResult.status, valid: appleResult.valid});
        } catch (e) {
          warn("verifyProPurchase: Apple API failed", {error: String(e)});
          throw new HttpsError("unavailable", "Unable to reach Apple API. Please try again.");
        }
      }

      if (!appleResult.valid) {
        throw new HttpsError(
          "failed-precondition",
          `Apple transaction invalid. status=${appleResult.status}`
        );
      }

      await db
        .collection("users")
        .doc(uid)
        .collection("purchases")
        .doc(kProProductId)
        .set({
          purchased_at: admin.firestore.FieldValue.serverTimestamp(),
          platform: "ios",
          order_id: appleResult.transactionId ?? orderId ?? "",
          product_id: kProProductId,
          purchase_token: purchaseToken,
          verified: true,
        });

      log("verifyProPurchase: iOS Firestore written OK", {uid});
      return {success: true};
    }

    // ── Android：呼叫 Google Play Developer API ──────────────────────────────
    let accessToken: string;
    try {
      accessToken = await getPlayAccessToken();
      log("verifyProPurchase: Play access token OK");
    } catch (e) {
      warn("verifyProPurchase: Play API auth failed", {
        error: String(e),
        errorType: e instanceof Error ? e.constructor.name : typeof e,
      });
      throw new HttpsError(
        "internal",
        "Play API authentication unavailable. Please try again later."
      );
    }

    const verifyUrl =
      `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/` +
      `${kPackageName}/purchases/products/${kProProductId}/tokens/${purchaseToken}`;

    let verifyRes: Response;
    try {
      verifyRes = await fetch(verifyUrl, {
        headers: {Authorization: `Bearer ${accessToken}`},
        signal: AbortSignal.timeout(15000),
      });
    } catch (e) {
      warn("verifyProPurchase: Play API fetch failed", {error: String(e)});
      throw new HttpsError("unavailable", "Unable to reach Play API. Please try again.");
    }

    if (!verifyRes.ok) {
      const errText = await verifyRes.text();
      warn("verifyProPurchase: Play API error", {
        status: verifyRes.status,
        body: errText.slice(0, 500),
        uid,
      });
      throw new HttpsError(
        "failed-precondition",
        `Play API returned ${verifyRes.status}`
      );
    }

    const playData = (await verifyRes.json()) as {
      purchaseState?: number; // 0=Purchased, 1=Canceled, 2=Pending
      acknowledgementState?: number; // 0=Yet to acknowledge, 1=Acknowledged
      orderId?: string;
    };

    if (playData.purchaseState !== 0) {
      throw new HttpsError(
        "failed-precondition",
        `Purchase not valid. state=${playData.purchaseState}`
      );
    }

    // Acknowledge if needed（防止 Google 自動退款）
    if (playData.acknowledgementState === 0) {
      const ackUrl = verifyUrl + ":acknowledge";
      await fetch(ackUrl, {
        method: "POST",
        headers: {Authorization: `Bearer ${accessToken}`},
        signal: AbortSignal.timeout(10000),
      }).catch((e) => warn("verifyProPurchase: acknowledge failed (non-fatal)", {error: String(e)}));
    }

    log("verifyProPurchase: Play API verified OK", {uid, orderId});

    // ── 寫入 Firestore ────────────────────────────────────────────────────────
    await db
      .collection("users")
      .doc(uid)
      .collection("purchases")
      .doc(kProProductId)
      .set({
        purchased_at: admin.firestore.FieldValue.serverTimestamp(),
        platform: "android",
        order_id: orderId ?? "",
        product_id: kProProductId,
        purchase_token: purchaseToken,
        verified: true,
      });

    log("verifyProPurchase: Firestore written OK", {uid});
    return {success: true};
  }
);

// ── Credit products map ───────────────────────────────────────────────────────

const kCreditProducts: Record<string, number> = {
  credits_08: 8,
  credits_24: 24,
  credits_80: 80,
};

// ── _addCreditsToAccount ──────────────────────────────────────────────────────
//
// 共用輔助函式：冪等性檢查 + 原子性入帳（iOS / Android 共用）
// idempotencyKey: iOS = transactionId，Android = purchaseToken
//
async function _addCreditsToAccount(
  uid: string,
  productId: string,
  credits: number,
  idempotencyKey: string
): Promise<{remainingCredits: number; alreadyFulfilled: boolean}> {
  const tokenRef = db.collection("purchaseTokens").doc(idempotencyKey);
  const userRef = db.collection("users").doc(uid);

  let remainingCredits = 0;
  let alreadyFulfilled = false;

  await db.runTransaction(async (tx) => {
    const tokenDoc = await tx.get(tokenRef);
    if (tokenDoc.exists) {
      const userDoc = await tx.get(userRef);
      remainingCredits = (userDoc.data()?.credits as number) ?? 0;
      alreadyFulfilled = true;
      return;
    }

    const userDoc = await tx.get(userRef);
    const currentCredits = (userDoc.data()?.credits as number) ?? 0;
    remainingCredits = currentCredits + credits;

    tx.set(tokenRef, {
      uid,
      productId,
      credits,
      fulfilledAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    tx.update(userRef, {
      credits: remainingCredits,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    writeCreditHistory(tx, uid, {
      type: "earned",
      amount: credits,
      reason: "purchase",
    });
  });

  return {remainingCredits, alreadyFulfilled};
}

// ── fulfillCreditPurchaseIOS ──────────────────────────────────────────────────
//
// iOS 專用：驗證 StoreKit 2 JWS Transaction → 冪等性入帳
//
// 1. 驗證 Firebase Auth
// 2. JWS 本地驗證（優先，不需 API Key）→ App Store Server API（fallback）
// 3. 冪等性檢查（防止重複入帳）
// 4. Firestore Transaction 原子性新增點數 + 寫 creditHistory

export const fulfillCreditPurchaseIOS = onCall(
  {
    region: "asia-east1",
    timeoutSeconds: 30,
    memory: "256MiB",
    invoker: "public",
    enforceAppCheck: false,
    secrets: [appStoreKeyId, appStoreIssuerId, appStorePrivateKey],
  },
  async (request) => {
    log("fulfillCreditPurchaseIOS: invoked", {
      hasAuth: !!request.auth,
      hasAppCheck: !!request.app,
    });
    const uid = await resolveUid(request);
    log("fulfillCreditPurchaseIOS: auth OK", {uid});

    const {purchaseToken, productId, jwsTransaction} = request.data as {
      purchaseToken: string;
      productId: string;
      jwsTransaction?: string;
    };

    if (!purchaseToken || !productId) {
      throw new HttpsError("invalid-argument", "purchaseToken and productId are required.");
    }

    const credits = kCreditProducts[productId];
    if (credits === undefined) {
      throw new HttpsError("invalid-argument", `Unknown productId: ${productId}`);
    }

    // ── Apple 交易驗證 ────────────────────────────────────────────────────────
    let appleResult: AppleVerifyResult;

    if (jwsTransaction) {
      // SK2 JWS 本地驗證（不需 API Key）
      try {
        appleResult = await verifyAppleJWSLocal(jwsTransaction, productId);
        log("fulfillCreditPurchaseIOS: local JWS verified", {uid, valid: appleResult.valid, productId});
      } catch (e) {
        warn("fulfillCreditPurchaseIOS: local JWS failed, falling back to API", {error: String(e)});
        appleResult = {valid: false, status: 0};
      }
      // 本地驗證失敗 → App Store Server API fallback
      if (!appleResult.valid) {
        try {
          appleResult = await verifyAppleTransaction(purchaseToken, productId);
          log("fulfillCreditPurchaseIOS: fallback API verified", {uid, status: appleResult.status, productId});
        } catch (e) {
          warn("fulfillCreditPurchaseIOS: Apple API fallback failed", {error: String(e)});
          throw new HttpsError("unavailable", "Unable to verify Apple purchase. Please try again.");
        }
      }
    } else {
      // 無 JWS（舊版 client 相容）→ App Store Server API
      try {
        appleResult = await verifyAppleTransaction(purchaseToken, productId);
        log("fulfillCreditPurchaseIOS: Apple API verified", {uid, status: appleResult.status, valid: appleResult.valid, productId});
      } catch (e) {
        warn("fulfillCreditPurchaseIOS: Apple API failed", {error: String(e)});
        throw new HttpsError("unavailable", "Unable to reach Apple API. Please try again.");
      }
    }

    if (!appleResult.valid) {
      throw new HttpsError(
        "failed-precondition",
        `Apple transaction invalid. status=${appleResult.status}`
      );
    }

    const transactionId = appleResult.transactionId ?? purchaseToken.slice(0, 1450);
    log("fulfillCreditPurchaseIOS: Apple verified OK", {uid, productId, transactionId});

    // ── 冪等性入帳 ────────────────────────────────────────────────────────────
    const {remainingCredits, alreadyFulfilled} =
      await _addCreditsToAccount(uid, productId, credits, transactionId);

    if (alreadyFulfilled) {
      log("fulfillCreditPurchaseIOS: already fulfilled (idempotent)", {uid, transactionId});
    } else {
      log("fulfillCreditPurchaseIOS: credits added", {uid, productId, credits, remainingCredits});
    }

    return {credits, remainingCredits, alreadyFulfilled};
  }
);

// ── fulfillCreditPurchaseAndroid ──────────────────────────────────────────────
//
// Android 專用：驗證 Google Play purchaseToken → 冪等性入帳
//
// 1. 驗證 Firebase Auth
// 2. 呼叫 Google Play Developer API 驗證 purchaseToken
// 3. 冪等性檢查（防止重複入帳）
// 4. Firestore Transaction 原子性新增點數 + 寫 creditHistory

export const fulfillCreditPurchaseAndroid = onCall(
  {
    region: "asia-east1",
    timeoutSeconds: 30,
    memory: "256MiB",
    invoker: "public",
    enforceAppCheck: false,
    serviceAccount: "github-play-store-deployer@magic-sticker-8eaf4.iam.gserviceaccount.com",
  },
  async (request) => {
    log("fulfillCreditPurchaseAndroid: invoked", {
      hasAuth: !!request.auth,
      hasAppCheck: !!request.app,
    });
    const uid = await resolveUid(request);
    log("fulfillCreditPurchaseAndroid: auth OK", {uid});

    const {purchaseToken, productId} = request.data as {
      purchaseToken: string;
      productId: string;
    };

    if (!purchaseToken || !productId) {
      throw new HttpsError("invalid-argument", "purchaseToken and productId are required.");
    }

    const credits = kCreditProducts[productId];
    if (credits === undefined) {
      throw new HttpsError("invalid-argument", `Unknown productId: ${productId}`);
    }

    // ── Google Play 交易驗證 ──────────────────────────────────────────────────
    let accessToken: string;
    try {
      accessToken = await getPlayAccessToken();
    } catch (e) {
      warn("fulfillCreditPurchaseAndroid: Play API auth failed", {error: String(e)});
      throw new HttpsError("internal", "Play API authentication unavailable. Please try again later.");
    }

    const verifyUrl =
      `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/` +
      `${kPackageName}/purchases/products/${productId}/tokens/${purchaseToken}`;

    let verifyRes: Response;
    try {
      verifyRes = await fetch(verifyUrl, {
        headers: {Authorization: `Bearer ${accessToken}`},
        signal: AbortSignal.timeout(15000),
      });
    } catch (e) {
      warn("fulfillCreditPurchaseAndroid: Play API fetch failed", {error: String(e)});
      throw new HttpsError("unavailable", "Unable to reach Play API. Please try again.");
    }

    if (!verifyRes.ok) {
      const errText = await verifyRes.text();
      warn("fulfillCreditPurchaseAndroid: Play API error", {
        status: verifyRes.status,
        body: errText.slice(0, 500),
        uid,
        productId,
      });
      throw new HttpsError("failed-precondition", `Play API returned ${verifyRes.status}`);
    }

    const playData = (await verifyRes.json()) as {
      purchaseState?: number; // 0=Purchased, 1=Canceled, 2=Pending
      acknowledgementState?: number;
      consumptionState?: number; // 0=Yet to consume, 1=Consumed
    };

    if (playData.purchaseState !== 0) {
      throw new HttpsError(
        "failed-precondition",
        `Purchase not valid. state=${playData.purchaseState}`
      );
    }

    log("fulfillCreditPurchaseAndroid: Play API verified OK", {uid, productId});

    // ── 冪等性入帳 ────────────────────────────────────────────────────────────
    const {remainingCredits, alreadyFulfilled} =
      await _addCreditsToAccount(uid, productId, credits, purchaseToken);

    if (alreadyFulfilled) {
      log("fulfillCreditPurchaseAndroid: already fulfilled (idempotent)", {uid, purchaseToken});
    } else {
      log("fulfillCreditPurchaseAndroid: credits added", {uid, productId, credits, remainingCredits});
    }

    return {credits, remainingCredits, alreadyFulfilled};
  }
);

// ── rewardAdCredit ────────────────────────────────────────────────────────────
//
// 看廣告後由 App 呼叫，Server 端原子性加 1 點並寫入 creditHistory。
// App 端無法直接寫 Firestore（Security Rules 封鎖），一律透過此 CF。
//
// 1. 驗證 Firebase Auth
// 2. Server-side 每日上限（台灣時區，2 次/日）via dailyRewardSummary
// 3. Firestore Transaction 原子性加 1 點 + 寫 creditHistory
// 4. 回傳 { granted, credits }

const kDailyAdLimit = 2;

export const rewardAdCredit = onCall(
  {
    region: "asia-east1",
    timeoutSeconds: 30,
    memory: "256MiB",
    invoker: "public",
    enforceAppCheck: false,
  },
  async (request) => {
    log("rewardAdCredit: invoked", {
      hasAuth: !!request.auth,
      hasAppCheck: !!request.app,
    });
    const uid = await resolveUid(request);
    log("rewardAdCredit: auth OK", {uid});

    const dateKey = todayKeyTW();
    const dailyRef = db
      .collection("users")
      .doc(uid)
      .collection("dailyRewardSummary")
      .doc(dateKey);
    const userRef = db.collection("users").doc(uid);

    let granted = false;
    let remainingCredits = 0;

    await db.runTransaction(async (tx) => {
      const [dailyDoc, userDoc] = await Promise.all([
        tx.get(dailyRef),
        tx.get(userRef),
      ]);

      const adCount = (dailyDoc.data()?.adCount as number) ?? 0;
      remainingCredits = (userDoc.data()?.credits as number) ?? 0;

      if (adCount >= kDailyAdLimit) {
        log("rewardAdCredit: daily limit reached", {uid, adCount});
        return; // 今日已達上限，冪等回傳
      }

      remainingCredits += 1;
      granted = true;

      tx.set(
        userRef,
        {
          credits: remainingCredits,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        {merge: true}
      );
      writeCreditHistory(tx, uid, {
        type: "earned",
        amount: 1,
        reason: "rewarded_ad",
      });
      tx.set(
        dailyRef,
        {
          adCount: adCount + 1,
          adLastGrantedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        {merge: true}
      );
    });

    log("rewardAdCredit: done", {uid, granted, remainingCredits});
    return {granted, credits: remainingCredits};
  }
);

// ── initUserSession ───────────────────────────────────────────────────────────
//
// App 啟動登入（含匿名）後呼叫，確保 Firestore users/{uid} 文件存在並回傳點數。
// 首次建立時分配初始點數（訪客 1 點 / 正式帳號 5 點）。
// 若文件已存在則直接回傳目前點數（冪等）。
//
// 1. 驗證 Firebase Auth
// 2. 若 users/{uid} 不存在，建立並給初始點數
// 3. 回傳 {credits, created}

const kGuestInitialCredits = 1;
const kNewAccountCredits = 5;

export const initUserSession = onCall(
  {
    region: "asia-east1",
    timeoutSeconds: 30,
    memory: "256MiB",
    invoker: "public",
    enforceAppCheck: false,
  },
  async (request) => {
    log("initUserSession: invoked", {
      hasAuth: !!request.auth,
      hasAppCheck: !!request.app,
    });
    const uid = await resolveUid(request);
    log("initUserSession: auth OK", {uid});

    // Auth token 中的 email（匿名用戶為 undefined）
    const tokenEmail = (request.auth?.token?.email as string | undefined) ?? null;

    const {anonCredits = 0, anonUid = ""} =
      (request.data ?? {}) as {anonCredits?: number; anonUid?: string};
    const mergeAmount = Math.max(0, Math.floor(anonCredits));

    const userRef = db.collection("users").doc(uid);
    let credits = 0;
    let created = false;

    await db.runTransaction(async (tx) => {
      const doc = await tx.get(userRef);
      if (doc.exists) {
        credits = (doc.data()?.credits as number) ?? 0;
        const updateFields: Record<string, unknown> = {};

        // 同步 email：首次登入正式帳號、或 email 有變更時補入
        if (tokenEmail && doc.data()?.email !== tokenEmail) {
          updateFields.email = tokenEmail;
          updateFields.updatedAt = admin.firestore.FieldValue.serverTimestamp();
        }

        // 合併匿名帳號點數（帳號切換時由 App 傳入）
        // 僅允許目標帳號仍為匿名狀態（isAnonymous: true）時合併；
        // 已綁定的正式帳號（isAnonymous: false）不接受合併，防止重複登出/登入刷點。
        if (mergeAmount > 0 && doc.data()?.isAnonymous === true) {
          credits += mergeAmount;
          updateFields.credits = credits;
          updateFields.updatedAt = admin.firestore.FieldValue.serverTimestamp();
          writeCreditHistory(tx, uid, {
            type: "earned",
            amount: mergeAmount,
            reason: "anon_merge",
          });
          // 合併後立即將匿名帳號 credits 歸零，防止重複登出/登入時再次 merge
          if (anonUid && anonUid !== uid) {
            const anonRef = db.collection("users").doc(anonUid);
            tx.set(anonRef, {credits: 0, updatedAt: admin.firestore.FieldValue.serverTimestamp()}, {merge: true});
          }
        }

        if (Object.keys(updateFields).length > 0) {
          tx.update(userRef, updateFields);
        }
        return;
      }

      // 判斷是否為匿名用戶（無 email、無 phone、無 provider）
      const userRecord = await admin.auth().getUser(uid);
      const isAnonymous =
        !userRecord.email &&
        !userRecord.phoneNumber &&
        (!userRecord.providerData || userRecord.providerData.length === 0);

      // 檢查 provider UID 黑名單：曾刪除過帳號的 provider 不再發放初始點數
      let wasDeleted = false;
      if (!isAnonymous) {
        for (const provider of userRecord.providerData ?? []) {
          const key = Buffer.from(`${provider.providerId}:${provider.uid}`)
            .toString("base64url");
          const snap = await tx.get(
            db.collection("_deletedProviders").doc(key)
          );
          if (snap.exists) {
            wasDeleted = true;
            break;
          }
        }
      }

      credits = isAnonymous
        ? kGuestInitialCredits
        : wasDeleted
        ? kGuestInitialCredits
        : kNewAccountCredits;
      created = true;

      tx.set(userRef, {
        credits,
        isAnonymous,
        ...(userRecord.email ? {email: userRecord.email} : {}),
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      writeCreditHistory(tx, uid, {
        type: "earned",
        amount: credits,
        reason: "new_account",
      });
    });

    log("initUserSession: done", {uid, credits, created, mergeAmount});
    return {credits, created};
  }
);

// ── getConfig ────────────────────────────────────────────────────────────────
//
// Debug 用：回傳目前部署的 model 設定（不需 Auth）

export const getConfig = onCall(
  {region: "asia-east1", timeoutSeconds: 10, memory: "128MiB", invoker: "public"},
  () => ({
    textModel: geminiTextModel.value(),
    imageModel: geminiImageModel.value(),
    functionsVersion: FUNCTIONS_VERSION,
  })
);

// ── 病毒成長輔助函式 ──────────────────────────────────────────────────────────

/** 無混淆字元的挑戰碼字集（排除 0/O/I/L/1），共 31 字元 */
const kCodeChars = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";

/** 隨機產生 length 碼的挑戰碼 */
function generateCode(length = 6): string {
  let result = "";
  for (let i = 0; i < length; i++) {
    result += kCodeChars[Math.floor(Math.random() * kCodeChars.length)];
  }
  return result;
}

/** 取得台灣時間（UTC+8）的日期 key，格式 yyyymmdd */
function todayKeyTW(): string {
  const now = new Date();
  const tw = new Date(now.getTime() + 8 * 60 * 60 * 1000);
  return tw.toISOString().slice(0, 10).replace(/-/g, "");
}

const kDomainBase = process.env.DOMAIN_BASE ?? "https://magic-sticker-8eaf4.web.app";

// ── ensureShareCode ───────────────────────────────────────────────────────────
//
// 分享時自動建立（或重用）挑戰碼 + deep link。
// 若同一 ownerUid 在最近 24h 內已有同 templateType 的有效 code，直接重用。
// 回傳 { code, deepLink, reused }。

export const ensureShareCode = onCall(
  {
    region: "asia-east1",
    timeoutSeconds: 15,
    memory: "256MiB",
    invoker: "public",
    enforceAppCheck: false,
  },
  async (request) => {
    log("ensureShareCode: invoked");
    const uid = await resolveUid(request);

    const {templateType, presetStyleIndex, presetCategoryIds,
           customStyleDesc, customEmotionDesc} =
      request.data as {
        templateType: "preset" | "pro_custom";
        presetStyleIndex?: number;
        presetCategoryIds?: string[];
        customStyleDesc?: string;
        customEmotionDesc?: string;
      };

    if (!templateType) {
      throw new HttpsError("invalid-argument", "templateType is required.");
    }

    const challengesRef = db.collection("challenges");
    const cutoff = new Date(Date.now() - 24 * 60 * 60 * 1000);

    // ── 嘗試重用 24h 內的有效 code ──────────────────────────────────────────
    // 需要 firestore.indexes.json 的 challenges 複合索引。
    // 若索引尚未建立完成，query 會拋出 9 FAILED_PRECONDITION；
    // catch 後降級：直接建立新 code（冪等性由 code 碰撞重試保證）。
    try {
      const existing = await challengesRef
        .where("ownerUid", "==", uid)
        .where("templateType", "==", templateType)
        .where("isActive", "==", true)
        .where("createdAt", ">=", cutoff)
        .limit(1)
        .get();

      if (!existing.empty) {
        const code = existing.docs[0].id;
        log("ensureShareCode: reusing existing code", {uid, code});
        return {code, deepLink: `${kDomainBase}/c/${code}`, reused: true};
      }
    } catch (e) {
      warn("ensureShareCode: reuse query failed (index missing?), will create new code", {
        error: String(e),
      });
    }

    // ── 建立新 code（碰撞重試最多 5 次）────────────────────────────────────
    let code = "";
    for (let attempt = 0; attempt < 5; attempt++) {
      const candidate = generateCode(6);
      const snap = await challengesRef.doc(candidate).get();
      if (!snap.exists) {
        code = candidate;
        break;
      }
    }

    if (!code) {
      throw new HttpsError("internal", "Failed to generate unique challenge code.");
    }

    const expiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000);
    await challengesRef.doc(code).set({
      code,
      ownerUid: uid,
      templateType,
      presetStyleIndex: presetStyleIndex ?? null,
      presetCategoryIds: presetCategoryIds ?? null,
      customStyleDesc: customStyleDesc ?? null,
      customEmotionDesc: customEmotionDesc ?? null,
      isActive: true,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      expiresAt,
    });

    log("ensureShareCode: new code created", {uid, code});
    return {code, deepLink: `${kDomainBase}/c/${code}`, reused: false};
  }
);

// ── shareRewardGrant ──────────────────────────────────────────────────────────
//
// 使用者點擊分享按鈕後呼叫；每日首次且 session 有 compare_screen_viewed 即 +1 點。
// 以 users/{uid}/dailyRewardSummary/{yyyymmdd}.shareGranted 作為冪等鎖。
// 回傳 { granted, newBalance, reason }。

export const shareRewardGrant = onCall(
  {
    region: "asia-east1",
    timeoutSeconds: 15,
    memory: "256MiB",
    invoker: "public",
    enforceAppCheck: false,
  },
  async (request) => {
    log("shareRewardGrant: invoked");
    const uid = await resolveUid(request);

    const {sessionHadCompareView} = request.data as {
      sessionHadCompareView: boolean;
    };

    if (!sessionHadCompareView) {
      log("shareRewardGrant: missing compare view signal", {uid});
      return {granted: false, newBalance: 0, reason: "missing_signal"};
    }

    const dateKey = todayKeyTW();
    const dailyRef = db
      .collection("users")
      .doc(uid)
      .collection("dailyRewardSummary")
      .doc(dateKey);
    const userRef = db.collection("users").doc(uid);

    let granted = false;
    let newBalance = 0;
    let reason = "already_claimed_today";

    await db.runTransaction(async (tx) => {
      const [dailyDoc, userDoc] = await Promise.all([
        tx.get(dailyRef),
        tx.get(userRef),
      ]);

      newBalance = (userDoc.data()?.credits as number) ?? 0;

      // 匿名用戶不給分享獎勵，防止「生成→分享→拿回點數→無限循環」
      if (userDoc.data()?.isAnonymous === true) {
        reason = "anon_user";
        return;
      }

      if (dailyDoc.exists && dailyDoc.data()?.shareGranted === true) {
        return; // 今日已領，冪等回傳
      }

      newBalance += 1;
      granted = true;
      reason = "";

      tx.set(
        userRef,
        {credits: newBalance, updatedAt: admin.firestore.FieldValue.serverTimestamp()},
        {merge: true}
      );
      writeCreditHistory(tx, uid, {type: "earned", amount: 1, reason: "share_reward"});
      tx.set(
        dailyRef,
        {shareGranted: true, shareGrantedAt: admin.firestore.FieldValue.serverTimestamp()},
        {merge: true}
      );
    });

    log("shareRewardGrant: done", {uid, granted, newBalance, dateKey});
    return {granted, newBalance, reason};
  }
);

// ── deleteUserAccount ────────────────────────────────────────────────────────
//
// App Store Guideline 5.1.1(v)：帳號刪除功能
// 1. 驗證 Firebase Auth
// 2. 刪除 users/{uid} 下所有子集合文件（creditHistory、purchases）
// 3. 刪除 users/{uid} 主文件
// 4. 刪除 Firebase Auth 用戶

async function deleteCollection(
  colRef: admin.firestore.CollectionReference,
  batchSize = 100
): Promise<void> {
  const query = colRef.limit(batchSize);
  while (true) {
    const snapshot = await query.get();
    if (snapshot.empty) break;
    const batch = db.batch();
    snapshot.docs.forEach((doc) => batch.delete(doc.ref));
    await batch.commit();
  }
}

export const deleteUserAccount = onCall(
  {
    region: "asia-east1",
    timeoutSeconds: 60,
    memory: "256MiB",
    invoker: "public",
    enforceAppCheck: false,
  },
  async (request) => {
    log("deleteUserAccount: invoked", {
      hasAuth: !!request.auth,
      hasAppCheck: !!request.app,
    });
    const uid = await resolveUid(request);
    log("deleteUserAccount: auth OK", {uid});

    try {
      // 刪除前，記錄 provider UID 黑名單，防止刪帳號後重複領初始點數
      const userRecord = await admin.auth().getUser(uid);
      if (userRecord.providerData && userRecord.providerData.length > 0) {
        const batch = db.batch();
        for (const provider of userRecord.providerData) {
          const key = Buffer.from(`${provider.providerId}:${provider.uid}`)
            .toString("base64url");
          const ref = db.collection("_deletedProviders").doc(key);
          batch.set(ref, {
            providerId: provider.providerId,
            providerUid: provider.uid,
            email: provider.email ?? null,
            deletedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        }
        await batch.commit();
        log("deleteUserAccount: provider blacklist saved", {
          uid,
          providers: userRecord.providerData.map((p) => p.providerId),
        });
      }

      const userRef = db.collection("users").doc(uid);

      // 刪除所有子集合
      const subcollections = await userRef.listCollections();
      log("deleteUserAccount: subcollections", {uid, count: subcollections.length});
      await Promise.all(
        subcollections.map((col) => deleteCollection(col))
      );

      // 刪除主文件
      await userRef.delete();
      log("deleteUserAccount: firestore doc deleted", {uid});

      // 刪除 Firebase Auth 用戶
      await admin.auth().deleteUser(uid);
      log("deleteUserAccount: auth user deleted", {uid});

      log("deleteUserAccount: done", {uid});
      return {success: true};
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : String(e);
      warn("deleteUserAccount: failed", {uid, error: msg});
      throw new HttpsError("internal", `刪除帳號失敗：${msg}`);
    }
  }
);
