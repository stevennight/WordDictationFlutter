import 'dart:async';
import 'dart:convert';
import 'base_block_generator.dart';
import '../config_service.dart';

/// Generator for definition block (senses, pronunciation, collocations)
/// Splits generation into two parallel tasks (Definition & Pronunciation) for higher accuracy
class DefinitionGenerator extends BaseBlockGenerator {
  DefinitionGenerator(ConfigService configService) : super(configService);

  @override
  String get blockName => 'Definition';

  @override
  Future<Map<String, dynamic>> generate({
    required String prompt,
    required String answer,
    String? sourceLanguage,
    String? targetLanguage,
    List<String>? sourcesHtml,
    List<Map<String, String>>? sourcesMeta,
    void Function()? onReflectionStart,
  }) async {
    // Build references once
    final referencesText = await buildReferencesTextWithConfig(sourcesHtml);

    // Run generation tasks in parallel
    final definitionFuture = _generateDefinitionPart(
      prompt: prompt,
      answer: answer,
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
      referencesText: referencesText,
    );

    final pronunciationFuture = _generatePronunciationPart(
      prompt: prompt,
      answer: answer,
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
      referencesText: referencesText,
    );

    // Wait for both results
    final results = await Future.wait([definitionFuture, pronunciationFuture]);
    final definitionPart = results[0];
    final pronunciationPart = results[1];

    // Merge results
    final mergedContent = {
      ...definitionPart,
      ...pronunciationPart,
    };

    return {'definition': mergedContent};
  }

  // Legacy/Stub implementation for abstract method
  @override
  Future<Map<String, dynamic>> generateBlock({
    required String prompt,
    required String answer,
    String? sourceLanguage,
    String? targetLanguage,
    List<String>? sourcesHtml,
    List<Map<String, String>>? sourcesMeta,
  }) async {
    throw UnimplementedError('Use generate() instead');
  }

  // --- Internal Generation Helpers ---

  Future<Map<String, dynamic>> _generateDefinitionPart({
    required String prompt,
    required String answer,
    String? sourceLanguage,
    String? targetLanguage,
    String? referencesText,
  }) async {
    final systemPrompt = _getDefinitionSystemPrompt();
    final userPrompt = getGenerationPrompt(
      prompt: prompt,
      answer: answer,
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
      referencesText: referencesText,
      forPronunciation: false,
    );

    // Initial Generation
    final generatedJson = await callAI(
      systemPrompt: systemPrompt,
      userPrompt: userPrompt,
      referencesText: referencesText,
    );

    // Validation (using exposed method from BaseBlockGenerator)
    return await validateAndCorrectWithRetry(
      prompt: prompt,
      answer: answer,
      generatedJson: generatedJson,
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
    );
  }

  Future<Map<String, dynamic>> _generatePronunciationPart({
    required String prompt,
    required String answer,
    String? sourceLanguage,
    String? targetLanguage,
    String? referencesText,
  }) async {
    final systemPrompt = _getPronunciationSystemPrompt();
    final userPrompt = getGenerationPrompt(
      prompt: prompt,
      answer: answer,
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
      referencesText: referencesText,
      forPronunciation: true,
    );

    // Initial Generation
    final generatedJson = await callAI(
      systemPrompt: systemPrompt,
      userPrompt: userPrompt,
      referencesText: referencesText,
    );

    // Validation
    return await validateAndCorrectWithRetry(
      prompt: prompt,
      answer: answer,
      generatedJson: generatedJson,
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
    );
  }

  // --- Prompts ---

  @override
  String getGenerationPrompt({
    required String prompt,
    required String answer,
    String? sourceLanguage,
    String? targetLanguage,
    String? referencesText,
    bool forPronunciation = false, // Added flag
  }) {
    final sb = StringBuffer();
    sb.write('单词为："$prompt"；单词词义为："$answer"。');
    if (referencesText != null && referencesText.isNotEmpty) {
      sb.write('\n请参考提供的"参考词典原始HTML"内容，提取准确的信息。');
    }
    
    if (forPronunciation) {
      sb.write('\n请按JSON结构返回 pronunciation 对象。');
    } else {
      sb.write('\n请按JSON结构返回 senses 和 collocations 对象。');
    }
    
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
    // Dispatch based on content
    if (generatedJson.contains('"pronunciation"')) {
      return _getPronunciationReflectionPrompt(prompt, answer, generatedJson, sourceLanguage, targetLanguage);
    } else {
      return _getDefinitionReflectionPrompt(prompt, answer, generatedJson, sourceLanguage, targetLanguage);
    }
  }

  // --- Definition Prompts (Senses + Collocations) ---

  String _getDefinitionSystemPrompt() {
    return r'''
只返回一个 JSON 对象，严禁输出除 JSON 外的任何内容。

格式要求：
- 严格合法 JSON（UTF-8，键用双引号）。
- 不输出解释、Markdown、示例或额外文本。
- 字段定义：
  - senses: 数组，义项列表。
    - pos: 词性标签（按目标语言规范）。
    - text: 简洁释义。
  - collocations: 数组（0-5项），固定搭配/惯用语。
    - textHtml: 原文（允许日语Ruby）。
    - translation: 译文。

Ruby 规则（仅日语）：
- 仅为汉字标注，格式：<ruby><rb>漢字</rb><rt>かんじ</rt></ruby>
- 禁止给假名、中文注音。

词性枚举（按目标语言输出；pos 必须从对应目标语言的规范标签中选择）：
- **严禁使用**："惯用语"、"短语"、"固定搭配"、"Phrase"、"Idiom" 等作为 pos 标签。
- **处理原则**：
  - **单词及其变形**：必须标注为原词词性（如 bought -> verb；apples -> noun）。
  - **短语/固定搭配**：**不标注词性**（省略 pos 字段，或留空）。
- zh（中文）：名词、动词、形容词、副词、介词、连词、代词、数词、量词、叹词、助词、连体词、助动词
- en（英文）：noun、verb、adjective、adverb、preposition、conjunction、pronoun、numeral、determiner、interjection、auxiliary
- ja（日文）：名詞、動詞、形容詞、形容動詞、副詞、連体詞、接続詞、感動詞、助詞、助動詞、接尾辞、接頭辞（動詞細分：一段動詞、五段動詞、サ変動詞、カ変動詞）
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
    - 接尾辞 → 接尾词
    - 接頭辞 → 接头词
- 其他语言对：若检测到不在目标语言规范标签中的别名或同义标签，应映射为该目标语言的规范标签。

JSON 示例：
{
  "senses": [
    {"pos": "名词", "text": "释义内容"}
  ],
  "collocations": [
    {"textHtml": "<ruby><rb>単語</rb><rt>たんご</rt></ruby>", "translation": "单词"}
  ]
}
''';
  }

  String _getDefinitionReflectionPrompt(String prompt, String answer, String generatedJson, String? sourceLanguage, String? targetLanguage) {
    return '''
你是一个严格的质量检查专家。请对以下AI生成的词解定义（释义与搭配）进行**极其严格**的验证。

原始单词：$prompt
词义：$answer
${sourceLanguage != null ? '源语言：$sourceLanguage' : ''}
${targetLanguage != null ? '目标语言：$targetLanguage' : ''}

生成的JSON：
$generatedJson

**检查清单**：
1. **释义准确性**：
   - 释义必须与输入"词义"一致。

2. **词性（POS）规范性**：
   - **单词及其变形**：必须标注为原词词性（如 bought -> verb）。
   - **短语/固定搭配**：**必须省略 pos 字段**。
   - **严禁使用**："惯用语"、"短语"等非枚举标签。
     - ❌ 错误：bought -> 惯用语
     - ❌ 错误：look for -> verb
     - ✅ 正确：bought -> verb
     - ✅ 正确：look for -> (无 pos 字段)

3. **搭配准确性**：
   - textHtml 必须是源语言真实搭配。
   - translation 必须准确。

4. **Ruby标注准确性（仅日语）**：
   - 仅为汉字注音，禁止给假名/中文注音。
   - 格式：<ruby><rb>漢字</rb><rt>かんじ</rt></ruby>

如果发现问题，返回JSON包含 `valid: false` 和 `issues`（含 field, problem, current, suggested）。
如果完全正确，返回 `{"valid": true}`。
''';
  }

  // --- Pronunciation Prompts ---

  String _getPronunciationSystemPrompt() {
    return r'''
只返回一个 JSON 对象，严禁输出除 JSON 外的任何内容。

格式要求：
- 严格合法 JSON。
- 字段定义：
  - pronunciation: 对象
    - text: 发音字符串（日语假名/英语IPA/中文拼音）。
    - tone: 声调字符串（日语⓪①.../其他空）。

**日语发音特别规则**：
- text: 仅假名，不含声调符号。
- tone: 使用⓪①②…，组合词用"+"连接。
- **动词ます形规则**：声调统一在ます的"ま"上（ma⬇️su）。
  * 无论原词声调，变成ます形后，声调核均在"ま"位置。
  * 例：食べる(2) → たべます(③, ta-be-ma-su)
  * 例：帰る(1) → かえります(④, ka-e-ri-ma-su)
  * 例：買う(0) → かいます(③, ka-i-ma-su)
  * 例：お願いします → おねがいします(⑥, o-ne-ga-i-shi-ma-su)
- 禁止标注原形读音。

JSON 示例：
{
  "pronunciation": {
    "text": "かいます",
    "tone": "③"
  }
}
''';
  }

  String _getPronunciationReflectionPrompt(String prompt, String answer, String generatedJson, String? sourceLanguage, String? targetLanguage) {
    return '''
你是一个严格的语言学专家。请对以下AI生成的发音信息进行**极其严格**的验证。

原始单词：$prompt
词义：$answer
生成的JSON：
$generatedJson

**检查清单**：
1. **日语发音（必须完全正确）**：
   - text 必须是假名（不含声调）。
   - tone 必须为⓪①②…格式。
   - **动词ます形读音规则**：
     - 统一规则：声调在ます的"ま"上（ma⬇️su）。
     - 无论原词声调类型，变成ます形后，声调核均在"ま"位置。
       * 例：食べる(2) → たべます(③)
       * 例：帰る(1) → かえります(④)
       * 例：買う(0) → かいます(③)
       * 例：お願いします → おねがいします(⑥)
       * 例：勉強します → べんきょうします(⑥)
     - **绝对禁止标注原形读音**：原词"買います"的发音必须是"かいます③"，不能是"かう②"

2. **英语/中文发音**：
   - 英语：IPA音标准确，tone为空。
   - 中文：拼音带声调，tone可空。

如果发现问题，返回JSON包含 `valid: false` 和 `issues`（含 field, problem, current, suggested）。
如果完全正确，返回 `{"valid": true}`。
''';
  }
}
