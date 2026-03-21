import * as admin from "firebase-admin";
import {onCall, HttpsError, CallableRequest} from "firebase-functions/v2/https";
import {defineSecret, defineString} from "firebase-functions/params";
import {log, warn} from "firebase-functions/logger";
import {GoogleAuth} from "google-auth-library";

admin.initializeApp();

const db = admin.firestore();
const geminiApiKey = defineSecret("GEMINI_API_KEY");
const geminiTextModel = defineString("GEMINI_TEXT_MODEL", {
  default: "gemini-2.5-flash",
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
    } = request.data as {
      photoBase64: string;
      categoryIds?: string[];
      customStyleDesc?: string;
      customEmotionDesc?: string;
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
                proHintSection + "\n\n" +
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

// ── verifyProPurchase ─────────────────────────────────────────────────────────
//
// 1. 驗證 Firebase Auth
// 2. 呼叫 Google Play Developer API 驗證 purchaseToken
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
    serviceAccount: "github-play-store-deployer@magic-sticker-8eaf4.iam.gserviceaccount.com",
  },
  async (request) => {
    log("verifyProPurchase: invoked", {
      hasAuth: !!request.auth,
      hasAppCheck: !!request.app,
    });
    const uid = await resolveUid(request);
    log("verifyProPurchase: auth OK", {uid});

    const {purchaseToken, orderId} = request.data as {
      purchaseToken: string;
      orderId?: string;
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

    // ── 呼叫 Google Play Developer API ──────────────────────────────────────
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

// ── fulfillCreditPurchase ─────────────────────────────────────────────────────
//
// 1. 驗證 Firebase Auth
// 2. 呼叫 Google Play Developer API 驗證 purchaseToken
// 3. 冪等性檢查（防止重複入帳）
// 4. Firestore Transaction 原子性新增點數 + 寫 creditHistory

const kCreditProducts: Record<string, number> = {
  credits_08: 8,
  credits_24: 24,
  credits_80: 80,
};

export const fulfillCreditPurchase = onCall(
  {
    region: "asia-east1",
    timeoutSeconds: 30,
    memory: "256MiB",
    invoker: "public",
    enforceAppCheck: false,
    serviceAccount: "github-play-store-deployer@magic-sticker-8eaf4.iam.gserviceaccount.com",
  },
  async (request) => {
    log("fulfillCreditPurchase: invoked", {
      hasAuth: !!request.auth,
      hasAppCheck: !!request.app,
    });
    const uid = await resolveUid(request);
    log("fulfillCreditPurchase: auth OK", {uid});

    const {purchaseToken, productId} = request.data as {
      purchaseToken: string;
      productId: string;
    };

    if (!purchaseToken || !productId) {
      throw new HttpsError(
        "invalid-argument",
        "purchaseToken and productId are required."
      );
    }

    const credits = kCreditProducts[productId];
    if (credits === undefined) {
      throw new HttpsError(
        "invalid-argument",
        `Unknown productId: ${productId}`
      );
    }

    // ── 呼叫 Google Play Developer API ──────────────────────────────────────
    let accessToken: string;
    try {
      accessToken = await getPlayAccessToken();
    } catch (e) {
      warn("fulfillCreditPurchase: Play API auth failed", {error: String(e)});
      throw new HttpsError(
        "internal",
        "Play API authentication unavailable. Please try again later."
      );
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
      warn("fulfillCreditPurchase: Play API fetch failed", {error: String(e)});
      throw new HttpsError("unavailable", "Unable to reach Play API. Please try again.");
    }

    if (!verifyRes.ok) {
      const errText = await verifyRes.text();
      warn("fulfillCreditPurchase: Play API error", {
        status: verifyRes.status,
        body: errText.slice(0, 500),
        uid,
        productId,
      });
      throw new HttpsError(
        "failed-precondition",
        `Play API returned ${verifyRes.status}`
      );
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

    log("fulfillCreditPurchase: Play API verified OK", {uid, productId});

    // ── 冪等性檢查 + 原子性入帳 ──────────────────────────────────────────────
    // purchaseTokens/{token} 作為已處理紀錄，防止重複入帳
    const tokenRef = db.collection("purchaseTokens").doc(purchaseToken);
    const userRef = db.collection("users").doc(uid);

    let remainingCredits = 0;
    let alreadyFulfilled = false;

    await db.runTransaction(async (tx) => {
      const tokenDoc = await tx.get(tokenRef);
      if (tokenDoc.exists) {
        // 已處理過，直接取目前點數回傳（冪等）
        const userDoc = await tx.get(userRef);
        remainingCredits = (userDoc.data()?.credits as number) ?? 0;
        alreadyFulfilled = true;
        return;
      }

      const userDoc = await tx.get(userRef);
      const currentCredits = (userDoc.data()?.credits as number) ?? 0;
      remainingCredits = currentCredits + credits;

      // 標記 token 已處理
      tx.set(tokenRef, {
        uid,
        productId,
        credits,
        fulfilledAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      // 新增點數
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

    if (alreadyFulfilled) {
      log("fulfillCreditPurchase: already fulfilled (idempotent)", {uid, purchaseToken});
    } else {
      log("fulfillCreditPurchase: credits added", {uid, productId, credits, remainingCredits});
    }

    return {credits, remainingCredits};
  }
);

// ── rewardAdCredit ────────────────────────────────────────────────────────────
//
// 看廣告後由 App 呼叫，Server 端原子性加 1 點並寫入 creditHistory。
// App 端無法直接寫 Firestore（Security Rules 封鎖），一律透過此 CF。
//
// 1. 驗證 Firebase Auth
// 2. Firestore Transaction 原子性加 1 點 + 寫 creditHistory
// 3. 回傳最新點數

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

    const userRef = db.collection("users").doc(uid);
    let remainingCredits = 0;

    await db.runTransaction(async (tx) => {
      const doc = await tx.get(userRef);
      const current = (doc.data()?.credits as number) ?? 0;
      remainingCredits = current + 1;
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
    });

    log("rewardAdCredit: +1 credit OK", {uid, remainingCredits});
    return {credits: remainingCredits};
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

    const userRef = db.collection("users").doc(uid);
    let credits = 0;
    let created = false;

    await db.runTransaction(async (tx) => {
      const doc = await tx.get(userRef);
      if (doc.exists) {
        credits = (doc.data()?.credits as number) ?? 0;
        return;
      }

      // 判斷是否為匿名用戶（無 email、無 phone、無 provider）
      const userRecord = await admin.auth().getUser(uid);
      const isAnonymous =
        !userRecord.email &&
        !userRecord.phoneNumber &&
        (!userRecord.providerData || userRecord.providerData.length === 0);

      credits = isAnonymous ? kGuestInitialCredits : kNewAccountCredits;
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

    log("initUserSession: done", {uid, credits, created});
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
  })
);
