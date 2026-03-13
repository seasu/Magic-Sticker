import * as admin from "firebase-admin";
import {onCall, HttpsError, CallableRequest} from "firebase-functions/v2/https";
import {defineSecret, defineString} from "firebase-functions/params";
import {log, warn} from "firebase-functions/logger";

admin.initializeApp();

const db = admin.firestore();
const geminiApiKey = defineSecret("GEMINI_API_KEY");
const geminiTextModel = defineString("GEMINI_TEXT_MODEL", {
  default: "gemini-2.0-flash-lite",
  description: "Gemini model for text/specs generation",
});
const geminiImageModel = defineString("GEMINI_IMAGE_MODEL", {
  default: "gemini-2.5-flash-image",
  description: "Gemini model for image generation",
});

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
  },
  async (request) => {
    // ★ 此行出現在 Firebase Logs = Cloud Run IAM 通過，function 程式碼有執行
    // 若 UNAUTHENTICATED 錯誤時此行消失 = IAM 攔截，需重新部署 invoker:public
    log("generateStickerSpecs: invoked", {
      hasAuth: !!request.auth,
      hasAuthHeader: !!request.rawRequest?.headers?.authorization,
    });
    const uid = await resolveUid(request);
    log("generateStickerSpecs: auth OK", {uid});

    const {photoBase64, categoryIds: rawCategoryIds} = request.data as {
      photoBase64: string;
      categoryIds?: string[];
    };

    if (!photoBase64) {
      throw new HttpsError("invalid-argument", "photoBase64 is required.");
    }

    // 情感類別 → 預設 8 種或由 client 指定（4–12 種）
    const DEFAULT_CATEGORY_IDS = [
      "greeting", "praise", "surprise", "awkward",
      "angry", "happy", "thinking", "farewell",
    ];
    const ids: string[] =
      Array.isArray(rawCategoryIds) && rawCategoryIds.length >= 4
        ? rawCategoryIds.slice(0, 12)
        : DEFAULT_CATEGORY_IDS;

    const CATEGORY_HINTS: Record<string, string> = {
      greeting: "cheerfully waving hello",
      praise: "excited thumbs-up with sparkles",
      surprise: "shocked wide eyes, question marks",
      awkward: "embarrassed blushing, sweat drop",
      angry: "angry frowning with flames",
      happy: "joyful laughing, rainbow confetti",
      thinking: "thoughtful chin-rubbing, thought bubble",
      farewell: "waving goodbye with sunglasses",
      shy: "shy blushing, covering face gently",
      cool: "smug cool confident sunglasses expression",
      tired: "tired droopy eyes, yawning heavily",
      cry: "crying tears flowing dramatically",
      love: "loving warm smile, heart eyes, rosy cheeks",
      excited: "star-struck excitement, jumping with joy",
      scared: "terrified wide eyes, trembling in fear",
      mischief: "playful mischievous wink, sticking out tongue",
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

    const body = {
      contents: [
        {
          parts: [
            {
              text:
                "你是一位創意 LINE 貼圖設計師，擅長根據照片人物的個性與氛圍，" +
                "設計出最適合的貼圖情感組合。\n\n" +
                "請仔細觀察照片中人物的外型、氣質、表情與場景，" +
                "依照以下情感類別清單（按順序），為他們設計專屬的 LINE 貼圖規格。\n\n" +
                `情感類別清單：[${categoryList}]\n\n` +
                "每個類別設計一張貼圖，輸出格式：僅回傳 JSON 陣列" +
                `（${ids.length} 個物件，順序與清單一致），每個物件包含：\n` +
                '- "categoryId": 對應情感類別 id（原樣回傳，不可修改）\n' +
                '- "text": 繁體中文標語（2–6 字，口語化有趣，適合貼圖）\n' +
                '- "emotion": 英文情感描述（用於繪製卡通表情，參考 promptHint 但可自由發揮）\n' +
                '- "bgColor": 背景色描述（英文色名 + hex，例如 "coral red #FF6B6B"）\n\n' +
                "範例格式（不要照抄，請根據照片創作）：\n" +
                '[{"categoryId":"greeting","text":"哈囉！","emotion":"cheerfully waving hello","bgColor":"warm peach #F4A261"}]',
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
      candidates: Array<{content: {parts: Array<{text?: string}>}}>;
    };

    const text = json.candidates?.[0]?.content?.parts
      ?.map((p) => p.text ?? "")
      .join("") ?? "";

    const match = text.match(/\[[\s\S]*\]/);
    if (!match) {
      throw new HttpsError("internal", "Invalid Gemini response format.");
    }

    const specs = JSON.parse(match[0]) as unknown[];
    if (!Array.isArray(specs) || specs.length < ids.length) {
      throw new HttpsError(
        "internal",
        `Gemini returned ${specs.length} specs, expected ${ids.length}.`
      );
    }

    return {specs: specs.slice(0, ids.length)};
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
  },
  async (request) => {
    // ★ 此行出現在 Firebase Logs = Cloud Run IAM 通過，function 程式碼有執行
    log("generateStickerImage: invoked", {
      hasAuth: !!request.auth,
      hasAuthHeader: !!request.rawRequest?.headers?.authorization,
    });
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
      candidates: Array<{
        content: {
          parts: Array<{
            inlineData?: {mimeType: string; data: string};
          }>;
        };
      }>;
    };

    const parts = json.candidates?.[0]?.content?.parts ?? [];
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
        reason: "no_image_returned",
      });
    });
    throw new HttpsError("internal", "No image returned by Gemini.");
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
  })
);
