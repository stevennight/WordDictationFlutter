import 'base_block_generator.dart';
import '../config_service.dart';

/// Generator for optional content blocks (highlights, synonyms, antonyms, extras)
class OptionalBlocksGenerator extends BaseBlockGenerator {
  OptionalBlocksGenerator(ConfigService configService) : super(configService);

  @override
  String get blockName => 'OptionalBlocks';

  @override
  Future<Map<String, dynamic>> generateBlock({
    required String prompt,
    required String answer,
    String? sourceLanguage,
    String? targetLanguage,
    List<String>? sourcesHtml,
    List<Map<String, String>>? sourcesMeta,
  }) async {
    final systemPrompt = _getSystemPrompt();
    final userPrompt = getGenerationPrompt(
      prompt: prompt,
      answer: answer,
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
    );

    final referencesText = await buildReferencesTextWithConfig(sourcesHtml);
    final result = await callAI(
      systemPrompt: systemPrompt,
      userPrompt: userPrompt,
      referencesText: referencesText,
    );

    // Return all optional blocks
    return {
      'highlights': result['highlights'] ?? [],
      'synonyms': result['synonyms'] ?? [],
      'antonyms': result['antonyms'] ?? [],
      'extras': result['extras'] ?? [],
    };
  }

  @override
  String getGenerationPrompt({
    required String prompt,
    required String answer,
    String? sourceLanguage,
    String? targetLanguage,
    String? referencesText,
  }) {
    final sb = StringBuffer();
    sb.write('单词为："$prompt"；单词词义为："$answer"。');
    if (referencesText != null && referencesText.isNotEmpty) {
      sb.write('\n请参考提供的"参考词典原始HTML"，优先提取其中的近义词、反义词、易错点和补充说明。');
    }
    sb.write('\n请按JSON结构返回highlights、synonyms、antonyms、extras。');
    return sb.toString();
  }

  @override
  String getReflectionPrompt({
    required String prompt,
    required String answer,
    required String generatedJson,
    String? sourceLanguage,
    String? targetLanguage,
  }) {
    return '''
你是一个严格的质量检查专家。请对以下AI生成的补充内容（易错点、近义词、反义词、补充说明）进行**极其严格**的准确性验证。

原始单词：$prompt
词义：$answer
${sourceLanguage != null ? '源语言（原文）：$sourceLanguage' : ''}
${targetLanguage != null ? '目标语言（译文）：$targetLanguage' : ''}

生成的JSON内容：
$generatedJson

**重要说明**：
- 源语言（原文）：单词本身的语言
- 目标语言（译文）：释义、翻译的语言
- **不要混淆原文和译文**
- **highlights 和 extras 是说明性内容，必须完全使用目标语言（译文）**
- 如需引用原文词汇，用「」包裹（日语原文可以在「」内加 ruby 标注）

**严格检查清单**：

1. **Highlights（易错点）准确性**：
   - textHtml 必须完全使用目标语言（译文）
   - 如需引用原文，用「」包裹，日语原文可以在「」内加 ruby
   - 例如：「<ruby><rb>列車</rb><rt>れっしゃ</rt></ruby>」是正确的
   - 必须是真实的易错点/注意点

2. **近义词/反义词准确性**：
   - 必须是真实的近义词/反义词
   - termHtml 是原文，必须有 ruby 标注（如果是日语）
   - 词形、读音必须正确，必须提供读音
   - **必须提供 termPronunciation（对象），且包含 text 字段**
   - **读音格式严格要求**：
     * 英语：IPA音标，如 /bʌɪ/ 或 /ˈkæpɪtl/
     * 日语：仅声调数字⓪①②③④⑤（假名已在ruby中显示，无需重复），如 ②、⑤、①
     * 中文：拼音+声调符号，如 mǎi、gòu、xíng
     * 其他语言：该语言通用的发音标注
   - **读音准确性验证**：
    * 日语：声调必须与termHtml中的词汇完全匹配，如果termHtml中包含变形，termPronunciation中必须为变形后的读音。
      * **重要：日语动词变形后声调会自然变化，这是正确的语音现象**
      * 正确示例：termHtml="<ruby><rb>購入</rb><rt>こうにゅう</rt></ruby>" → termPronunciation={"text":"⓪"}
      * 正确示例：termHtml="<ruby><rb>購入します</rb><rt>こうにゅうします</rt></ruby>" → termPronunciation={"text":"⑥"}（变形后声调变化正确）
      * 错误示例：termHtml="<ruby><rb>買う</rb><rt>かう</rt></ruby>" → termPronunciation={"text":"かいます③"}（不应包含假名）
      * 错误示例：termHtml="<ruby><rb>買</rb><rt>か</rt></ruby>う" → termPronunciation={"text":"③"}（读音非termHtml中变形后的读音）
    * 英语：音标必须准确反映词汇的实际发音
    * 中文：拼音声调必须正确
   - **近义词和反义词都必须提供读音标注，不能遗漏**
   - 区别说明、例句必须准确
   - differenceHtml 等说明字段使用译文，引用原文用「」包裹，日语原文可以在「」内加 ruby

3. **Extras（补充说明）准确性**：
   - textHtml 必须完全使用目标语言（译文）
   - 如需引用原文，用「」包裹，日语原文可以在「」内加 ruby
   - 必须是真实的补充说明，比如一些人文的知识、生活化的用法、典故等。

4. **Ruby标注准确性（日语）**：
   - 仅当源语言（原文）为日语时，才允许标注 ruby
   - **仅为日语汉字部分标注ruby，不包括假名部分**
   - 平假名、片假名、中文等其他字符禁止标注ruby
   - 正确示例：買う→<ruby><rb>買</rb><rt>か</rt></ruby>う、行って→<ruby><rb>行</rb><rt>い</rt></ruby>って
   - 错误示例：不要将整个"買って"包装为<ruby><rb>買って</rb><rt>かって</rt></ruby>
   - 允许合理的拆词标注：复合词（如忘れ物）可按语素拆分，但熟字训（如今日→きょう）必须保持整体
   - 判断标准：当每个汉字对应其合理的读音部分时可拆分（如忘れ→わすれ、物→もの），但当读音为整体约定时不可拆分
   - 语音变化规则：各种语音变化（促音便、連濁、濁化等）属于可拆分范围，因为语素边界仍然可识别
     - 可拆分：真っ青（まっさお=真+青，連濁）、立って（たって=立つ+て，促音便）、雨（あめ=あま+濁化）
     - 不可拆分：今日（きょう）、昨日（きのう）、一寸（ちょっと）等熟字训
   - ruby 格式：<ruby><rb>…</rb><rt>…</rt></ruby>。
   - 没有需要 ruby 标注的内容时，则与 plain 内容没有任何区别。
   - 若源语言（原文）非日语，则禁止任何 ruby 标注（包括译文与引用）。

**验证标准**：宁可严格，不可放松。任何疑似错误都应标记为问题。

只返回一个 JSON 对象，严禁输出除 JSON 外的任何内容；禁止使用 Markdown 代码块或 ```json 包裹。

如果**所有内容完全准确无误**：
{"valid": true}

如果发现**任何问题**：
{
  "valid": false,
  "issues": [
    {
      "field": "具体字段路径",
      "problem": "具体问题描述",
      "current": "当前错误的内容",
      "suggested": "建议修正后的内容"
    }
  ]
}

**重要**：每个问题必须包含 current（当前错误内容）和 suggested（建议修正内容），以便修正AI能够准确替换。
''';
  }

  String _getSystemPrompt() {
    return r'''
只返回一个 JSON 对象，严禁输出除 JSON 外的任何内容；禁止使用 Markdown 代码块或 ```json 包裹。

格式要求：
- 严格合法 JSON（UTF-8，键用双引号，字符串用双引号，数组/对象无尾逗号）。
- 不输出解释、Markdown、示例或额外文本。
- 所有字符串去除首尾空白。
- 对不可确定的内容，省略该字段或返回空数组；不要返回 null。

字段定义：
highlights
- 数组，0–5项，尽可能多。每项对象：
  - textHtml: 易错点/注意点说明（目标语言（译文）；允许在「…」中引述少量原文，日语原文可以在「」内带 ruby）。
  - 例如：「<ruby><rb>列車</rb><rt>れっしゃ</rt></ruby>」是正确的
  - 必须是真实的易错点/注意点

synonyms
- 数组，0–5项，尽可能多。每项对象：
  - termHtml: 近义词词形（源语言（原文）；如果是日语必须有 ruby）。
  - termPronunciation: 近义词读音，要求必须有读音标注（对象，必须包含 text 字段）。
  - **读音格式严格要求**：
    * 英语：IPA音标，如 /bʌɪ/ 或 /ˈkæpɪtl/
    * 日语：仅声调数字⓪①②③④⑤（假名已在ruby中显示，无需重复），如 ②、⑤、①
      * **重要：日语动词变形后声调会自然变化，这是正确的语音现象**
      * 例如：購入⓪ → 購入します⑥、買う⓪ → 買います③
    * 中文：拼音+声调符号，如 mǎi、gòu、xíng
    * 其他语言：该语言通用的发音标注
  - gloss: 近义词简要含义。
  - differenceHtml: 与当前词的区别（目标语言（译文）；允许在「…」中引述少量原文，日语原文可以在「」内带 ruby）。
  - selfHtml: 使用当前词的例句（源语言（原文）；允许 ruby）。
  - selfTranslation: 上述例句译文。
  - synHtml: 使用近义词的例句（源语言（原文）；允许 ruby）。
  - synTranslation: 上述例句译文。

antonyms
- 数组，0–5项，尽可能多。每项对象：
  - termHtml: 反义词词形（源语言（原文）；如果是日语必须有 ruby）。
  - termPronunciation: 反义词读音，要求必须有读音标注（对象，必须包含 text 字段）。
  - **读音格式严格要求**：
    * 英语：IPA音标，如 /bʌɪ/ 或 /ˈkæpɪtl/
    * 日语：仅声调数字⓪①②③④⑤（假名已在ruby中显示，无需重复），如 ②、⑤、①
      * **重要：日语动词变形后声调会自然变化，这是正确的语音现象**
      * 例如：購入⓪ → 購入します⑥、買う⓪ → 買います③
    * 中文：拼音+声调符号，如 mǎi、gòu、xíng
    * 其他语言：该语言通用的发音标注
  - gloss: 反义词简要含义。
  - exampleHtml: 使用反义词的例句（源语言（原文）；允许 ruby）。
  - exampleTranslation: 上述例句译文。

extras
- 数组，0–5项，尽可能多。每项对象：
  - textHtml: 与该词相关的简短补充说明（目标语言（译文）；允许在「…」中引述少量原文，日语原文可以在「」内带 ruby）。
  - 必须是真实的补充说明，比如一些人文的知识、生活化的用法、典故等。

ruby 规则：
- 仅当源语言（原文）为日语时，才允许标注 ruby
- **仅为日语汉字部分标注ruby，不包括假名部分**
- 平假名、片假名、中文等其他字符禁止标注ruby
- 正确示例：買う→<ruby><rb>買</rb><rt>か</rt></ruby>う、行って→<ruby><rb>行</rb><rt>い</rt></ruby>って
- 错误示例：不要将整个"買って"包装为<ruby><rb>買って</rb><rt>かって</rt></ruby>
- 允许合理的拆词标注：复合词（如忘れ物）可按语素拆分，但熟字训（如今日→きょう）必须保持整体
- 判断标准：当每个汉字对应其合理的读音部分时可拆分（如忘れ→わすれ、物→もの），但当读音为整体约定时不可拆分
- 语音变化规则：各种语音变化（促音便、連濁、濁化等）属于可拆分范围，因为语素边界仍然可识别
  - 可拆分：真っ青（まっさお=真+青，連濁）、立って（たって=立つ+て，促音便）、雨（あめ=あま+濁化）
  - 不可拆分：今日（きょう）、昨日（きのう）、一寸（ちょっと）等熟字训
- ruby 格式：<ruby><rb>…</rb><rt>…</rt></ruby>。
- 若源语言（原文）非日语，则禁止任何 ruby 标注（包括译文与引用）。
- **重要**：highlights 和 extras 的 textHtml 必须使用目标语言（译文）书写
- differenceHtml 等说明性字段也必须使用目标语言（译文）
- 如需引用原文词汇，用「」包裹，日语原文可以在「」内加 ruby
- termHtml、selfHtml、synHtml、exampleHtml 等原文字段可以直接使用 ruby（如果是日语）

生成约束：
- 严格依据提供的单词（prompt）与词义（answer）。
- 生成的内容尽可能完善，不遗漏任何重要信息。

**重要提示**：
- highlights 和 extras 的 textHtml 必须使用目标语言（译文）书写
- differenceHtml 等说明性字段也必须使用目标语言（译文）
- 如需引用原文词汇，用「」包裹，日语原文可以在「」内加 ruby
- termHtml、selfHtml、synHtml、exampleHtml 等原文字段可以直接使用 ruby（如果是日语）

JSON 响应示例（日语→中文）：
{
  "highlights": [
    {
      "textHtml": "「アルバイト」多指在特定场所（如商店、咖啡馆）工作，而「<ruby><rb>内職</rb><rt>ないしょく</rt></ruby>」则特指在家中进行的副业。"
    }
  ],
  "synonyms": [
    {
      "termHtml": "アルバイト",
      "termPronunciation": {"text": "アルバイト⓪"},
      "gloss": "兼职工作",
      "differenceHtml": "「アルバイト」多指在特定场所工作，而「<ruby><rb>内職</rb><rt>ないしょく</rt></ruby>」则特指在家中进行的副业。",
      "selfHtml": "<ruby><rb>彼女</rb><rt>かのじょ</rt></ruby>は<ruby><rb>内職</rb><rt>ないしょく</rt></ruby>で<ruby><rb>生活費</rb><rt>せいかつひ</rt></ruby>を<ruby><rb>稼</rb><rt>かせ</rt></ruby>いでいる。",
      "selfTranslation": "她通过在家做副业来赚取生活费。",
      "synHtml": "<ruby><rb>学生</rb><rt>がくせい</rt></ruby>の<ruby><rb>頃</rb><rt>ころ</rt></ruby>、カフェでアルバイトをしていた。",
      "synTranslation": "学生时代在咖啡馆打工。"
    }
  ],
  "antonyms": [
    {
      "termHtml": "<ruby><rb>本業</rb><rt>ほんぎょう</rt></ruby>",
      "termPronunciation": {"text": "ほんぎょう⓪"},
      "gloss": "主业、正职",
      "exampleHtml": "<ruby><rb>彼</rb><rt>かれ</rt></ruby>は<ruby><rb>本業</rb><rt>ほんぎょう</rt></ruby>は<ruby><rb>会社員</rb><rt>かいしゃいん</rt></ruby>だ。",
      "exampleTranslation": "他的正职是公司职员。"
    }
  ],
  "extras": [
    {
      "textHtml": "在德语中，「Arbeit」除了指劳动、工作外，也可指学问上的业绩、研究成果。"
    }
  ]
}
''';
  }
}
