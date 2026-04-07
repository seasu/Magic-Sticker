import * as admin from "firebase-admin";
import * as crypto from "node:crypto";
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
const FUNCTIONS_VERSION = "1.1.5";

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

    const {photoBase64, prompt} = request.data as {
      photoBase64: string;
      prompt: string;
    };

    if (!photoBase64 || !prompt) {
      throw new HttpsError(
        "invalid-argument",
        "photoBase64 and prompt are required."
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
            {text: prompt},
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
        // 合併匿名帳號點數（帳號切換時由 App 傳入）
        // 僅允許目標帳號仍為匿名狀態（isAnonymous: true）時合併；
        // 已綁定的正式帳號（isAnonymous: false）不接受合併，防止重複登出/登入刷點。
        if (mergeAmount > 0 && doc.data()?.isAnonymous === true) {
          credits += mergeAmount;
          tx.update(userRef, {
            credits,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
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
