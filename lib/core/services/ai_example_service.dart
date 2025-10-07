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
    } else {
      rules.add('自动识别原词语言并用于 textPlain 与 textHtml。');
    }
    if (langTarget.isNotEmpty) {
      rules.add('textTranslation 使用 '+langTarget+'，提供完整句子译文。');
    } else {
      rules.add('自动识别最合适的词义语言，并提供完整句子译文。');
    }

    final baseSystem = '你是一名负责生成「例句」的助手，请严格按要求返回数据。'
        '例句应地道、简洁、符合常用表达，避免生僻词或不自然的搭配。'
        '严格只返回一个 JSON 数组（不包含任何额外文本或解释），数组每项必须包含：'
        'senseIndex（数字）、senseText（字符串）、textPlain（字符串）、textHtml（字符串）、textTranslation（字符串）、grammarNote（字符串）。'
        '不要返回 Markdown 或除 JSON 之外的任意内容。'
        '质量要求：'
        '1）各例句之间语法结构与场景尽量差异化；'
        '2）textPlain 长度适中（约10–40词或等效字数），语法正确、自然；'
        '3）textTranslation 与该词义严格一致，为整句完整译文，避免意译导致语义偏离；'
        '4）grammarNote 使用译文语言书写，仅说明句中真实出现的语法点；多个语法点用 \\n 分隔（JSON 中必须使用 \\n，而非实际换行或 \\r\\n）；'
        '5）避免重复或模板化的句式。'
        'textHtml 规则：若原文为日文或中文则使用 ruby 标注；否则令 textHtml 与 textPlain 相同，不包含任何 HTML 标签。'
        '如果例句是日文：为例句中出现的汉字都添加 ruby，禁止漏标；仅对「汉字」添加 ruby，不要对假名（ひらがな/カタカナ）或拉丁字符添加 ruby；严格遵循 <ruby><rb>汉字</rb><rt>かな</rt></ruby> 的形式标注，rt 使用平假名，不要使用罗马音；示例：「<ruby><rb>私</rb><rt>わたし</rt></ruby>は<ruby><rb>学校</rb><rt>がっこう</rt></ruby>に<ruby><rb>行</rb><rt>い</rt></ruby>きました。」。'
        '如果例句是中文：为整句所有汉字添加拼音 ruby（<ruby><rb>汉字</rb><rt>pinyin</rt></ruby>），不要对拉丁字符或符号添加 ruby；允许一个 ruby 中包含多组 <rb>/<rt>。';
    final system = [baseSystem, ...rules].join(' ');

    final user = '原词：'+prompt+
        '。词义（带索引）：'+
        List.generate(senses.length, (i) => '【'+i.toString()+'】'+senses[i]).join('；')+
        '。请严格生成恰好 '+expectedCount.toString()+' 条例句，每条对应一个词义。'
        '输出要求：仅输出一个 JSON 数组，长度为 '+expectedCount.toString()+'；'
        '数组中每项的键必须为：senseIndex、senseText、textPlain、textHtml、textTranslation、grammarNote。'
        '映射要求：senseIndex 必须对应上面提供的编号；senseText 必须「严格复制」对应词义文本（不要增删或改写）。';

    // 简短 Few-shot 示例，用于稳定格式与风格（不长、但可示范）
    final fewShotUser = '原词：light。词义（带索引）：【0】亮光；【1】轻的。请严格生成恰好 2 条例句，每条对应一个词义。'
        '输出要求：仅输出一个 JSON 数组，长度为 2；'
        '数组中每项的键必须为：senseIndex、senseText、textPlain、textHtml、textTranslation、grammarNote。'
        '映射要求：senseIndex 必须对应上面提供的编号；senseText 必须严格复制对应词义文本（不要增删或改写）。';

    final fewShotAssistant = '''[
  {
    "senseIndex": 0,
    "senseText": "亮光",
    "textPlain": "The room was filled with soft light.",
    "textHtml": "The room was filled with soft light.",
    "textTranslation": "房间里充满了柔和的光线。",
    "grammarNote": "被动语态\r\n形容词修饰名词"
  },
  {
    "senseIndex": 1,
    "senseText": "轻的",
    "textPlain": "The suitcase is light, so she carried it easily.",
    "textHtml": "The suitcase is light, so she carried it easily.",
    "textTranslation": "这个手提箱很轻，所以她轻松地提着它。",
    "grammarNote": "形容词作表语\r\n并列句"
  }
]''';

    // 超短的日文 ruby 示例 Few-shot（演示正确的 ruby 与键名）
    final fewShotUserJa = '原词：明るい。词义（带索引）：【0】明亮的；【1】开朗的。请严格生成恰好 2 条例句，每条对应一个词义。'
        '输出要求：仅输出一个 JSON 数组，长度为 2；'
        '数组中每项的键必须为：senseIndex、senseText、textPlain、textHtml、textTranslation、grammarNote。'
        '映射要求：senseIndex 必须对应上面提供的编号；senseText 必须严格复制对应词义文本（不要增删或改写）。';

    final fewShotAssistantJa = '''[
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