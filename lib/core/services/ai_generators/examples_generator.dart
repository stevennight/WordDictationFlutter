import 'base_block_generator.dart';
import '../config_service.dart';

/// Generator for examples block
class ExamplesGenerator extends BaseBlockGenerator {
  ExamplesGenerator(ConfigService configService) : super(configService);

  @override
  String get blockName => 'Examples';

  @override
  Future<Map<String, dynamic>> generateBlock({
    required String prompt,
    required String answer,
    String? sourceLanguage,
    String? targetLanguage,
    List<String>? sourcesHtml,
    List<Map<String, String>>? sourcesMeta,
  }) async {
    final referencesText = await buildReferencesTextWithConfig(sourcesHtml);
    
    final systemPrompt = _getSystemPrompt();
    final userPrompt = getGenerationPrompt(
      prompt: prompt,
      answer: answer,
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
    );

    final result = await callAI(
      systemPrompt: systemPrompt,
      userPrompt: userPrompt,
      referencesText: referencesText,
    );

    return {'examples': result['examples'] ?? []};
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
      sb.write('\n可以参考提供的"参考词典原始HTML"中的例句，但需要确保符合当前词义，并生成准确的译文。');
    }
    sb.write('\n请按JSON结构返回examples数组。');
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
你是一个严格的质量检查专家。请对以下AI生成的例句内容进行**极其严格**的准确性验证。

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

**严格检查清单**：

1. **例句准确性**：
   - textHtml 必须是源语言（原文），语法完全正确，用词地道自然
   - textTranslation 必须是目标语言（译文），翻译准确
   - senseText 必须与"词义"（answer）对应
   - 每个词义必须对应一个例句
   - 不要混淆：例句本身是原文，翻译才是译文

2. **Ruby标注准确性（日语）**：
   - 仅当源语言（原文）为日语时，才允许标注 ruby
   - 仅为包含日语汉字的部分（含单个汉字）整体标注 ruby
   - 平假名、片假名、中文等其他字符禁止标注ruby
   - 允许合理的拆词标注：复合词（如忘れ物）可按语素拆分，但熟字训（如今日→きょう）必须保持整体
   - 判断标准：当每个汉字对应其合理的读音部分时可拆分（如忘れ→わすれ、物→もの），但当读音为整体约定时不可拆分
   - 语音变化规则：各种语音变化（促音便、連濁、濁化等）属于可拆分范围，因为语素边界仍然可识别
     - 可拆分：真っ青（まっさお=真+青，連濁）、立って（たって=立つ+て，促音便）、雨（あめ=あま+濁化）
     - 不可拆分：今日（きょう）、昨日（きのう）、一寸（ちょっと）等熟字训
   - ruby 格式：<ruby><rb>…</rb><rt>…</rt></ruby>。
   - 没有需要 ruby 标注的内容时，则与 plain 内容没有任何区别。
   - 若源语言（原文）非日语，则禁止任何 ruby 标注（包括译文与引用）。

3. **语法点标注准确性**：
   - grammarNotes 中的语法点必须真实存在
   - 必须与例句中实际使用的语法对应
   - 说明必须准确

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

字段定义：
examples
- 数组，与传入的词义（answer）一一对应，每个词义生成一个例句。如果 answer 包含多个词义（如"1. 词义A；2. 词义B"），则生成多个例句。每项对象：
  - senseText: 该例句对应的词义，必须是 answer 中的原文词义内容。
  - textHtml: 例句内容（源语言（原文）；允许 ruby）。
  - textTranslation: 例句译文（目标语言（译文））。
  - grammarNotes: 数组，该例句中用到的语法点（目标语言（译文））。

ruby 规则：
- 仅当源语言（原文）为日语时，才允许标注 ruby。
- 仅为包含日语汉字的部分（含单个汉字）整体标注 ruby。
- 平假名、片假名、中文等其他字符禁止标注ruby。
- 允许合理的拆词标注：复合词（如忘れ物）可按语素拆分，但熟字训（如今日→きょう）必须保持整体
- 判断标准：当每个汉字对应其合理的读音部分时可拆分（如忘れ→わすれ、物→もの），但当读音为整体约定时不可拆分
- 语音变化规则：各种语音变化（促音便、連濁、濁化等）属于可拆分范围，因为语素边界仍然可识别
  - 可拆分：真っ青（まっさお=真+青，連濁）、立って（たって=立つ+て，促音便）、雨（あめ=あま+濁化）
  - 不可拆分：今日（きょう）、昨日（きのう）、一寸（ちょっと）等熟字训
- ruby 格式：<ruby><rb>…</rb><rt>…</rt></ruby>。
- 若源语言（原文）非日语，则禁止任何 ruby 标注（包括译文与引用）。

生成约束：
- 例句尽可能使用一些高级用法，以便用户复习语法内容。
- 严格依据提供的单词（prompt）与词义（answer）。

JSON 响应示例（日语→中文，假设 answer 为"打工"）：
{
  "examples": [
    {
      "senseText": "打工",
      "textHtml": "<ruby><rb>彼</rb><rt>かれ</rt></ruby>は<ruby><rb>喫茶店</rb><rt>きっさてん</rt></ruby>でアルバイトをしている。",
      "textTranslation": "他在咖啡店打工。",
      "grammarNotes": ["で表示场所", "ている表示持续状态"]
    }
  ]
}
''';
  }
}
