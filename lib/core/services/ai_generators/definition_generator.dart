import 'dart:convert';
import 'base_block_generator.dart';
import '../config_service.dart';

/// Generator for definition block (senses, pronunciation, collocations)
class DefinitionGenerator extends BaseBlockGenerator {
  DefinitionGenerator(ConfigService configService) : super(configService);

  @override
  String get blockName => 'Definition';

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
      referencesText: referencesText,
    );

    final result = await callAI(
      systemPrompt: systemPrompt,
      userPrompt: userPrompt,
      referencesText: referencesText,
    );

    return {'definition': result};
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
      sb.write('\n请参考提供的"参考词典原始HTML"内容，提取准确的释义、发音和搭配信息。');
    }
    sb.write('\n请按JSON结构返回definition对象。');
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
你是一个严格的质量检查专家。请对以下AI生成的词解定义内容进行**极其严格**的准确性验证。

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

1. **发音准确性（必须完全正确）**：
   - 日语：假名拼写、声调标记（⓪①②等）必须与原词完全一致
   - 英语：IPA 音标必须准确
   - 中文：拼音及声调必须正确
   - **发音准确性验证**：
     * 日语：读音必须与原词完全匹配，动词变形后读音必须与变形后的读音一致
      * 正确示例：原词"買う" → 发音"かう②"
      * 错误示例：原词"買います" → 发音"かう②"（未根据原词变形后的读音）
     * 英语：音标必须准确反映词汇的实际发音
     * 中文：拼音声调必须正确
   - 绝不允许发音错误

2. **释义准确性**：
   - 释义必须与输入的"词义"（answer）完全对应
   - 不能添加、遗漏或曲解原意
   - 词性标注必须正确（按源语言体系判断类别，按目标语言输出规范标签；必须严格按照下方"词性枚举"中的规范标签和POS规范化规则）

3. **搭配/熟语准确性**：
   - textHtml 必须是源语言（原文）的真实搭配、熟语或谚语
   - translation 必须是目标语言（译文）的准确翻译
   - 不能随意组合词语

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

词性枚举（按目标语言输出；pos 必须从对应目标语言的规范标签中选择）：
- zh（中文）：名词、动词、形容词、副词、介词、连词、代词、数词、量词、叹词、助词、连体词、助动词
- en（英文）：noun、verb、adjective、adverb、preposition、conjunction、pronoun、numeral、determiner、interjection、auxiliary
- ja（日文）：名詞、動詞、形容詞、形容動詞、副詞、連体詞、接続詞、感動詞、助詞、助動詞（動詞細分：一段動詞、五段動詞、サ変動詞、カ変動詞）
- other（其他）：noun、verb、adjective、adverb、pronoun、preposition、conjunction、interjection、determiner、particle、auxiliary、classifier

POS 规范化（别名映射与示例）：
- 当源语言为日语、目标语言为中文时：
  - 日→中词性对应表：
    - 名詞 → 名词
    - 動詞 → 动词
    - 形容詞 → 形容词
    - 形容動詞 → 形容动词
    - 副詞 → 副词
    - 連体詞 → 连体词
    - 接続詞 → 连词
    - 感動詞 → 叹词
    - 助詞 → 助词
    - 助動詞 → 助动词
    - 一段動詞 → 一段动词
    - 五段動詞 → 五段动词
    - サ変動詞 → サ变动词
    - カ変動詞 → カ变动词
- 其他语言对：若检测到不在目标语言规范标签中的别名或同义标签，应映射为该目标语言的规范标签。

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
definition
- senses: 数组，相同词性但是意思不同的情况下分为多个子项。每项对象：
  - pos: 词性标签，必须从对应语言的枚举列表中选择，使用目标语言（译文）描述。
  - text: 该义项的简洁释义。
- pronunciation: 对象，必须包含
  - text: 发音字符串。格式要求：
    - 英语：使用 IPA 音标，如 /həˈləʊ/
    - 日语：使用假名+声调数字（⓪①②…），如 がくせい⓪
    - 中文：使用拼音+声调符号，如 nǐ hǎo
    - 其他语言：使用该语言通用的标准发音标注
- collocations: 数组，0–5项，尽可能多。
  - 仅收录：固定搭配（Collocations）、惯用语（Idioms）、谚语、成语。
  - 严禁：临时造句或松散的词语组合（例如 "在便利店打工" 这种普通短语属于例句，不属于搭配）。
  - 每项对象：
    - textHtml: 搭配/熟语内容（源语言（原文）；允许 ruby）。
    - translation: 对应译文（目标语言（译文））。

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

词性枚举（pos 必须从对应目标语言的规范标签中选择）：
- zh（中文）：名词、动词、形容词、副词、介词、连词、代词、数词、量词、叹词、助词、连体词、助动词
- en（英文）：noun、verb、adjective、adverb、preposition、conjunction、pronoun、numeral、determiner、interjection、auxiliary
- ja（日文）：名詞、動詞、形容詞、形容動詞、副詞、連体詞、接続詞、感動詞、助詞、助動詞（動詞細分：一段動詞、五段動詞、サ変動詞、カ変動詞）
- other（其他）：noun、verb、adjective、adverb、pronoun、preposition、conjunction、interjection、determiner、particle、auxiliary、classifier

POS 规范化（别名映射与示例）：
- 当源语言为日语、目标语言为中文时：
  - 日→中词性对应表：
    - 名詞 → 名词
    - 動詞 → 动词
    - 形容詞 → 形容词
    - 形容動詞 → 形容动词
    - 副詞 → 副词
    - 連体詞 → 连体词
    - 接続詞 → 连词
    - 感動詞 → 叹词
    - 助詞 → 助词
    - 助動詞 → 助动词
    - 一段動詞 → 一段动词
    - 五段動詞 → 五段动词
    - サ変動詞 → サ変动词
    - カ変動詞 → カ変动词
- 其他语言对：若检测到不在目标语言规范标签中的别名或同义标签，应映射为该目标语言的规范标签。

生成约束：
- 严格依据提供的单词（prompt）与词义（answer）。
- 生成的内容尽可能完善，不遗漏任何重要信息。

JSON 响应示例（日语→中文）：
{
  "senses": [
    {
      "pos": "名词",
      "text": "在家中进行的副业，多为手工劳动或简单加工。"
    }
  ],
  "pronunciation": {
    "text": "ないしょく①"
  },
  "collocations": [
    {
      "textHtml": "<ruby><rb>内職</rb><rt>ないしょく</rt></ruby><ruby><rb>募集</rb><rt>ぼしゅう</rt></ruby>",
      "translation": "招聘在家副业"
    },
    {
      "textHtml": "<ruby><rb>在宅</rb><rt>ざいたく</rt></ruby><ruby><rb>勤務</rb><rt>きんむ</rt></ruby>",
      "translation": "在家办公"
    }
  ]
}
''';
  }
}
