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

    final langSource = sourceLanguage?.trim();
    final langTarget = targetLanguage?.trim();

    final system = 'You are a helpful assistant generating example sentences. '
        'Return ONLY a valid JSON array. Each item MUST have keys: '
        'senseIndex (number), '
        'textPlain (string), '
        'textHtml (string), '
        'textTranslation (string). '
        'Do NOT include markdown fences, extra text, or explanations.';

    final List<String> rules = [];
    if (langSource != null && langSource.isNotEmpty) {
      rules.add('Use '+langSource+' for textPlain and textHtml.');
    } else {
      rules.add('Auto-detect the original sentence language from the "Original word" and use it for textPlain and textHtml.');
    }
    if (langTarget != null && langTarget.isNotEmpty) {
      rules.add('Provide textTranslation in '+langTarget+' as a complete translation.');
    } else {
      rules.add('Auto-detect the translation language from the meanings or the most appropriate target, and provide a complete translation in that language.');
    }

    final user = 'Original word: '+prompt+
        '. Meanings (indexed): '+
        List.generate(senses.length, (i) => '[$i] '+senses[i]).join('; ')+
        '. Generate exactly '+expectedCount.toString()+' example sentences, one per meaning index. '
        + rules.join(' ')+
        ' Keep textPlain concise and natural, and include ruby in textHtml where appropriate.';

    final body = jsonEncode({
      'model': model,
      'messages': [
        {'role': 'system', 'content': system},
        {'role': 'user', 'content': user},
      ],
      'temperature': 0.7,
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
        result.add(ExampleSentence(
          id: null,
          wordId: 0, // caller should set correct wordId when inserting
          senseIndex: (item['senseIndex'] ?? 0) is int ? item['senseIndex'] as int : int.tryParse('${item['senseIndex']}') ?? 0,
          textPlain: (item['textPlain'] ?? '').toString(),
          textHtml: (item['textHtml'] ?? '').toString(),
          textTranslation: (item['textTranslation'] ?? '').toString(),
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
}