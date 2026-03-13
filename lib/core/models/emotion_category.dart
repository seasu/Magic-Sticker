/// 預設情感類別定義
///
/// [kEmotionCategories] 共 16 種，前 8 種為預設選中（[defaultOn] = true）。
/// 使用者可在情感選擇器中選取 4–12 種來生成貼圖。
class EmotionCategory {
  final String id;
  final String label;       // 中文類別名，如「打招呼」
  final String emoji;       // 代表 emoji，如「👋」
  final String promptHint;  // 英文描述，傳入 Gemini prompt
  final bool defaultOn;     // 是否預設選中

  const EmotionCategory({
    required this.id,
    required this.label,
    required this.emoji,
    required this.promptHint,
    required this.defaultOn,
  });
}

/// 16 種預設情感類別
///
/// 前 8 種為預設選中（打招呼/讚美/驚訝/尷尬/生氣/開心/思考/道別），
/// 後 8 種為可額外選取的擴充選項。
const kEmotionCategories = <EmotionCategory>[
  // ── 預設 8 種（defaultOn: true）─────────────────────────────
  EmotionCategory(id: 'greeting', label: '打招呼', emoji: '👋', promptHint: 'cheerfully waving hello',                       defaultOn: true),
  EmotionCategory(id: 'praise',   label: '讚美',   emoji: '👍', promptHint: 'excited thumbs-up with sparkles',               defaultOn: true),
  EmotionCategory(id: 'surprise', label: '驚訝',   emoji: '😲', promptHint: 'shocked wide eyes, question marks',             defaultOn: true),
  EmotionCategory(id: 'awkward',  label: '尷尬',   emoji: '😅', promptHint: 'embarrassed blushing, sweat drop',              defaultOn: true),
  EmotionCategory(id: 'angry',    label: '生氣',   emoji: '😤', promptHint: 'angry frowning with flames',                    defaultOn: true),
  EmotionCategory(id: 'happy',    label: '開心',   emoji: '😄', promptHint: 'joyful laughing, rainbow confetti',             defaultOn: true),
  EmotionCategory(id: 'thinking', label: '思考',   emoji: '🤔', promptHint: 'thoughtful chin-rubbing, thought bubble',       defaultOn: true),
  EmotionCategory(id: 'farewell', label: '道別',   emoji: '🫡', promptHint: 'waving goodbye with sunglasses',                defaultOn: true),
  // ── 額外 8 種（defaultOn: false）────────────────────────────
  EmotionCategory(id: 'shy',      label: '害羞',   emoji: '🥹', promptHint: 'shy blushing, covering face gently',            defaultOn: false),
  EmotionCategory(id: 'cool',     label: '得意',   emoji: '😎', promptHint: 'smug cool confident sunglasses expression',     defaultOn: false),
  EmotionCategory(id: 'tired',    label: '疲倦',   emoji: '😩', promptHint: 'tired droopy eyes, yawning heavily',            defaultOn: false),
  EmotionCategory(id: 'cry',      label: '哭泣',   emoji: '😢', promptHint: 'crying tears flowing dramatically',             defaultOn: false),
  EmotionCategory(id: 'love',     label: '愛心',   emoji: '🥰', promptHint: 'loving warm smile, heart eyes, rosy cheeks',   defaultOn: false),
  EmotionCategory(id: 'excited',  label: '興奮',   emoji: '🤩', promptHint: 'star-struck excitement, jumping with joy',      defaultOn: false),
  EmotionCategory(id: 'scared',   label: '害怕',   emoji: '😱', promptHint: 'terrified wide eyes, trembling in fear',        defaultOn: false),
  EmotionCategory(id: 'mischief', label: '調皮',   emoji: '😜', promptHint: 'playful mischievous wink, sticking out tongue', defaultOn: false),
];

/// 依 id 查找 EmotionCategory，找不到回傳 null
EmotionCategory? findCategory(String id) {
  for (final c in kEmotionCategories) {
    if (c.id == id) return c;
  }
  return null;
}

/// 預設選中的 8 個 categoryId
final kDefaultCategoryIds = kEmotionCategories
    .where((c) => c.defaultOn)
    .map((c) => c.id)
    .toList();
