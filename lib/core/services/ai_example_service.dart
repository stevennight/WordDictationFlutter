import 'dart:convert';
import 'package:http/http.dart' as http;

import '../../shared/models/example_sentence.dart';
import 'config_service.dart';

class AIExampleService {
  static AIExampleService? _instance;
  final ConfigService _configService;

  AIExampleService._(this._configService);

  static Future<AIExampleService> getInstance() async {
    _instance ??= AIExampleService._(await ConfigService.getInstance());
    return _instance!;
  }

  /// 根据原文与译文（分号/；分隔不同意思）生成例句
  /// 每个意思生成一条例句，并返回包含整体译文字段
  /// 语言按次选择（可选）：
  /// - sourceLanguage：例句原文语言（textPlain/textHtml），未设置则自动识别
  /// - targetLanguage：例句完整译文语言（textTranslation），未设置则自动识别
  Future<List<ExampleSentence>> generateExamples({
    required String prompt,
    required String answer,
    String? sourceLanguage,
    String? targetLanguage,
  }) async {
    final endpoint = await _configService.getAIEndpoint();
    final apiKey = await _configService.getAIApiKey();
    final model = await _configService.getAIModel();
    final temperature = await _configService.getAITemperature();

    if (apiKey.isEmpty) {
      throw Exception('AI API key is not set');
    }

    final uri = Uri.parse(_normalizeEndpoint(endpoint, path: '/chat/completions'));
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $apiKey',
    };

    final senses = _splitSenses(answer);
    final expectedCount = senses.length;

    // 不在程序内做语言识别：当未指定语言时，让 AI 自行识别
    final langSource = (sourceLanguage?.trim().isNotEmpty ?? false)
        ? sourceLanguage!.trim()
        : '';
    final langTarget = (targetLanguage?.trim().isNotEmpty ?? false)
        ? targetLanguage!.trim()
        : '';

    final List<String> rules = [];
    if (langSource.isNotEmpty) {
      rules.add('textPlain 与 textHtml 使用 '+langSource+'。');
      rules.add('单词为 $langSource，该语言用于生成例句内容。');
    } else {
      rules.add('自动识别单词语言，该语言用于生成例句内容。');
    }
    if (langTarget.isNotEmpty) {
      rules.add('单词词义为 $langTarget，该语言用于生成例句翻译、例句语法讲解。');
    } else {
      rules.add('自动识别单词词义语言，该语言用于生成例句翻译、例句语法讲解。');
    }

    const baseSystem = '你是一名负责生成「例句」的助手，请严格按要求返回数据。'
        '例句应地道、简洁、符合常用表达，避免生僻词或不自然的搭配。'
        '严格只返回一个 JSON 数组（不包含任何额外文本或解释），数组每项必须包含：'
        'senseIndex（数字）、senseText（字符串）、textPlain（字符串）、textHtml（字符串）、textTranslation（字符串）、grammarNote（字符串）。'
        '不要返回 Markdown 或除 JSON 之外的任意内容。'
        '质量要求：'
        '1）各例句之间语法结构与场景尽量差异化；'
        '2）textPlain 长度适中（约20–60词或等效字数），语法正确、自然；只保留句子本身。'
        '3）textTranslation 与该词义严格一致，为整句完整译文，避免意译导致语义偏离；只保留句子本身。'
        '4）grammarNote ，仅说明句中真实出现的语法点；多个语法点用 \\n 分隔（JSON 中必须使用 \\n，而非实际换行或 \\r\\n）；'
        '5）避免重复或模板化的句式；尽可能用一些常用的语法、语法结构。'
        'textHtml 规则：'
        '如果例句是日文：'
        '例句中的所有汉字的部分需要添加 ruby 注音，禁止漏标；'
        '注音用假名标注，不要用罗马字；'
        '禁止为平假名、片假名或拉丁字符的单词添加注音ruby，但句子中的汉字仍要添加注音ruby。'
        '注意日文汉字的音读与训读，以及量词的音变等。'
        '严格遵循 <ruby><rb>汉字</rb><rt>かな</rt></ruby> 的形式标注，rt 使用平假名，不要使用罗马音；'
        'ruby生成时注意标签的闭合准确。';
    final system = [baseSystem, ...rules].join('\n');

    String answerWithIndex = List.generate(senses.length, (i) => '【$i】${senses[i]}').join('；');
    final user = [
      '单词为："$prompt"；单词词义（带索引）为："$answerWithIndex"。',
      '请严格生成恰好 $expectedCount 条例句，每条对应一个词义。',
      '输出要求：仅输出一个 JSON 数组，长度为 $expectedCount；',
      '数组中每项的键必须为：senseIndex、senseText、textPlain、textHtml、textTranslation、grammarNote。',
      '映射要求：senseIndex 必须对应上面提供的编号；senseText 必须「严格复制」对应词义文本（不要增删或改写）。',
      ...rules
    ].join('\n');

    // 简短 Few-shot 示例，用于稳定格式与风格（不长、但可示范）
    const fewShotUser = '单词为："light"；单词词义（带索引）为："【0】亮光；【1】轻的"。'
        '输出要求：仅输出一个 JSON 数组，长度为 2；'
        '数组中每项的键必须为：senseIndex、senseText、textPlain、textHtml、textTranslation、grammarNote。'
        '映射要求：senseIndex 必须对应上面提供的编号；senseText 必须严格复制对应词义文本（不要增删或改写）。';

    const fewShotAssistant = '''[
  {
    "senseIndex": 0,
    "senseText": "亮光",
    "textPlain": "The room was filled with soft light.",
    "textHtml": "The room was filled with soft light.",
    "textTranslation": "房间里充满了柔和的光线。",
    "grammarNote": "被动语态\\n形容词修饰名词"
  },
  {
    "senseIndex": 1,
    "senseText": "轻的",
    "textPlain": "The suitcase is light, so she carried it easily.",
    "textHtml": "The suitcase is light, so she carried it easily.",
    "textTranslation": "这个手提箱很轻，所以她轻松地提着它。",
    "grammarNote": "形容词作表语\\n并列句"
  }
]''';

    // 超短的日文 ruby 示例 Few-shot（演示正确的 ruby 与键名）
    const fewShotUserJa = '单词为："明るい"；单词词义（带索引）为："【0】明亮的；【1】开朗的"。'
        '输出要求：仅输出一个 JSON 数组，长度为 2；'
        '数组中每项的键必须为：senseIndex、senseText、textPlain、textHtml、textTranslation、grammarNote。'
        '映射要求：senseIndex 必须对应上面提供的编号；senseText 必须严格复制对应词义文本（不要增删或改写）。';

    const fewShotAssistantJa = '''[
  {
    "senseIndex": 0,
    "senseText": "明亮的",
    "textPlain": "この部屋はとても明るい。",
    "textHtml": "この<ruby><rb>部屋</rb><rt>へや</rt></ruby>はとても<ruby><rb>明</rb><rt>あか</rt></ruby>るい。",
    "textTranslation": "这个房间很明亮。",
    "grammarNote": "主題助詞「は」标示主题\\n副词「とても」修饰形容词\\n形容词「明るい」作谓语"
  },
  {
    "senseIndex": 1,
    "senseText": "开朗的",
    "textPlain": "彼は性格が明るい。",
    "textHtml": "<ruby><rb>彼</rb><rt>かれ</rt></ruby>は<ruby><rb>性格</rb><rt>せいかく</rt></ruby>が<ruby><rb>明</rb><rt>あか</rt></ruby>るい。",
    "textTranslation": "他性格开朗。",
    "grammarNote": "主題助詞「は」标示主题\\n主格助词「が」标示『性格』为主语\\n形容词「明るい」作谓语"
  }
]''';

    final body = jsonEncode({
      'model': model,
      'messages': [
        {'role': 'system', 'content': system},
        {'role': 'user', 'content': fewShotUser},
        {'role': 'assistant', 'content': fewShotAssistant},
        {'role': 'user', 'content': fewShotUserJa},
        {'role': 'assistant', 'content': fewShotAssistantJa},
        {'role': 'user', 'content': user},
      ],
      'temperature': temperature,
    });

    final resp = await http.post(uri, headers: headers, body: body);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('AI request failed: ${resp.statusCode} ${resp.body}');
    }

    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    final content = decoded['choices']?[0]?['message']?['content'] as String? ?? '';

    final examplesJson = _extractJsonArray(content);
    final examplesList = examplesJson != null ? jsonDecode(examplesJson) as List<dynamic> : <dynamic>[];

    final ts = DateTime.now();

    final List<ExampleSentence> result = [];
    for (final item in examplesList) {
      if (item is Map<String, dynamic>) {
        final idx = (item['senseIndex'] ?? 0) is int ? item['senseIndex'] as int : int.tryParse('${item['senseIndex']}') ?? 0;
        final senseText = (item['senseText'] ?? '').toString();
        result.add(ExampleSentence(
          id: null,
          wordId: 0, // caller should set correct wordId when inserting
          senseIndex: idx,
          senseText: senseText,
          textPlain: (item['textPlain'] ?? '').toString(),
          textHtml: (item['textHtml'] ?? '').toString(),
          textTranslation: (item['textTranslation'] ?? '').toString(),
          grammarNote: (item['grammarNote'] ?? '').toString(),
          sourceModel: model,
          createdAt: ts,
          updatedAt: ts,
        ));
      }
    }

    return result;
  }


  List<String> _splitSenses(String answer) {
    return answer
        .split(RegExp(r'[;；]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  String _normalizeEndpoint(String endpoint, {required String path}) {
    final base = endpoint.endsWith('/') ? endpoint.substring(0, endpoint.length - 1) : endpoint;
    final p = path.startsWith('/') ? path : '/$path';
    return '$base$p';
  }

  String? _extractJsonArray(String content) {
    final start = content.indexOf('[');
    final end = content.lastIndexOf(']');
    if (start >= 0 && end > start) {
      final jsonPart = content.substring(start, end + 1);
      return jsonPart;
    }
    return null;
  }

  String? _extractJsonObject(String content) {
    final start = content.indexOf('{');
    final end = content.lastIndexOf('}');
    if (start >= 0 && end > start) {
      return content.substring(start, end + 1);
    }
    return null;
  }

}