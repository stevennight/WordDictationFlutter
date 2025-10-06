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

    // Auto-detect languages when not provided
    final autoSource = _detectSourceLanguageFromPrompt(prompt);
    final autoTarget = _detectTargetLanguageFromAnswer(senses, answer);

    final langSource = (sourceLanguage?.trim().isNotEmpty ?? false)
        ? sourceLanguage!.trim()
        : autoSource;
    final langTarget = (targetLanguage?.trim().isNotEmpty ?? false)
        ? targetLanguage!.trim()
        : autoTarget;

    final system = '你是一名负责生成「例句」的助手，请严格按要求返回数据。'
        '只返回一个合法的 JSON 数组，每一项必须包含以下键：'
        'senseIndex（数字）、textPlain（字符串）、textHtml（字符串）、textTranslation（字符串）、grammarNote（字符串）。'
        '不要返回 Markdown、额外解释或任何非 JSON 内容。'
        '每个条目的 senseIndex 必须严格对应给定词义索引；textTranslation 必须与该词义语义一致，为整句完整译文；'
        'grammarNote 必须仅列出句子中真实出现的语法点（必须能在 textPlain 或 textHtml 中找到对应的词或形态），未出现的语法不得列出（例如未使用「です」就不得写「です」）。用译文语言编写，多个语法之间换行。单个语法说明的格式为：【语法内容，如...です】语法说明'
        '如果原文是日文：仅对「汉字」添加 ruby，不要对假名（ひらがな/カタカナ）或拉丁字符添加 ruby；为整句所有出现的汉字序列都添加 ruby，不得漏标；使用 <ruby><rb>汉字</rb><rt>かな</rt></ruby>，rt 使用平假名，不要使用罗马音。例如：「<ruby><rb>私</rb><rt>わたし</rt></ruby>は<ruby><rb>学校</rb><rt>がっこう</rt></ruby>に<ruby><rb>行</rb><rt>い</rt></ruby>きました。」'
        '如果原文是中文：为整句所有汉字添加拼音 ruby（<ruby><rb>汉字</rb><rt>pinyin</rt></ruby>），不要对拉丁字符或符号添加 ruby；允许一个 ruby 中包含多组 <rb>/<rt>。';

    final List<String> rules = [];
    if (langSource.isNotEmpty) {
      rules.add('textPlain 与 textHtml 使用 '+langSource+'。');
      final ls = langSource.toLowerCase();
      if (ls.startsWith('jap')) {
        rules.add('为整句所有汉字添加日文假名 ruby（<ruby><rb>..</rb><rt>..</rt></ruby>，rt 用平假名）。');
      } else if (ls.startsWith('chinese')) {
        rules.add('为整句所有汉字添加中文拼音 ruby（<ruby><rb>..</rb><rt>pinyin</rt></ruby>）。');
      }
    } else {
      rules.add('自动识别原文语言并用于 textPlain 与 textHtml。');
      rules.add('若识别为日文：为整句所有汉字添加假名 ruby；若识别为中文：为整句所有汉字添加拼音 ruby。');
    }
    if (langTarget.isNotEmpty) {
      rules.add('textTranslation 使用 '+langTarget+'，提供完整句子译文。');
      rules.add('grammarNote 使用 '+langTarget+'，格式：【<语法>】：语法解释。');
    } else {
      rules.add('自动识别最合适的译文语言，并提供完整句子译文。');
      rules.add('grammarNote 使用译文语言，格式：【<语法>】：语法解释。');
    }

    final user = '原词：'+prompt+
        '。词义（带索引）：'+
        List.generate(senses.length, (i) => '【'+i.toString()+'】'+senses[i]).join('；')+
        '。请严格按索引生成恰好 '+expectedCount.toString()+' 条例句，每条对应一个词义索引。'
        + rules.join(' ')+
        ' 每条例句需：基于 senseIndex 对应词义设定语境；textTranslation 与该词义保持一致；textPlain 简洁自然；textHtml 在整句范围对所有汉字提供 ruby（仅对汉字添加，假名不加），允许一个 ruby 中包含多组 <rb>/<rt>；grammarNote（译文语言）仅列出句中真实出现的语法，格式为【<语法>】：语法解释。';

    final body = jsonEncode({
      'model': model,
      'messages': [
        {'role': 'system', 'content': system},
        {'role': 'user', 'content': user},
      ],
      'temperature': 0.2,
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
          grammarNote: (item['grammarNote'] ?? '').toString(),
          sourceModel: model,
          createdAt: ts,
          updatedAt: ts,
        ));
      }
    }

    return result;
  }

  /// 支持分步/并行生成：按词义逐条生成例句，并通过 onProgress 回调报告进度
  /// parallel 指并行度（>=1），默认 1 串行；返回所有生成的例句列表
  Future<List<ExampleSentence>> generateExamplesProgress({
    required String prompt,
    required String answer,
    String? sourceLanguage,
    String? targetLanguage,
    int parallel = 1,
    void Function(int done, int total)? onProgress,
  }) async {
    final endpoint = await _configService.getAIEndpoint();
    final apiKey = await _configService.getAIApiKey();
    final model = await _configService.getAIModel();

    if (apiKey.isEmpty) {
      throw Exception('AI API key is not set');
    }

    final senses = _splitSenses(answer);
    final total = senses.length;
    if (total == 0) return [];

    // 语言处理（与 generateExamples 保持一致）
    final autoSource = _detectSourceLanguageFromPrompt(prompt);
    final autoTarget = _detectTargetLanguageFromAnswer(senses, answer);
    final langSource = (sourceLanguage?.trim().isNotEmpty ?? false) ? sourceLanguage!.trim() : autoSource;
    final langTarget = (targetLanguage?.trim().isNotEmpty ?? false) ? targetLanguage!.trim() : autoTarget;

    // 构造通用的系统提示与规则
    final system = '你是一名负责生成「例句」的助手，请严格按要求返回数据。'
        '只返回一个合法的 JSON 对象，必须包含以下键：'
        'senseIndex（数字）、textPlain（字符串）、textHtml（字符串）、textTranslation（字符串）、grammarNote（字符串）。'
        '不要返回 Markdown、额外解释或任何非 JSON 内容。'
        'textTranslation 必须与该词义语义一致，为整句完整译文；'
        'grammarNote 指出句子使用到的语法，用译文语言编写，多个语法之间换行。单个语法说明的格式为：【语法内容，如...です】<语法说明>'
        '如果原文是日文，整句所有「汉字」都需要标注假名（ruby），不仅仅是目标词：使用 <ruby><rb>汉字</rb><rt>かな</rt></ruby>，可在一个 ruby 中包含多组 <rb>/<rt> 配对，rt 使用平假名，不要使用罗马音。'
        '如果原文是中文，需要为整句所有「汉字」标注拼音（ruby），格式同上：<ruby><rb>汉字</rb><rt>pinyin</rt></ruby>，允许多组 <rb>/<rt>。';

    final List<String> rules = [];
    if (langSource.isNotEmpty) {
      rules.add('textPlain 与 textHtml 使用 '+langSource+'。');
      final ls = langSource.toLowerCase();
      if (ls.startsWith('jap')) {
        rules.add('为整句所有汉字添加日文假名 ruby（<ruby><rb>..</rb><rt>..</rt></ruby>，rt 用平假名）。');
      } else if (ls.startsWith('chinese')) {
        rules.add('为整句所有汉字添加中文拼音 ruby（<ruby><rb>..</rb><rt>pinyin</rt></ruby>）。');
      }
    } else {
      rules.add('自动识别原文语言并用于 textPlain 与 textHtml。');
      rules.add('若识别为日文：为整句所有汉字添加假名 ruby；若识别为中文：为整句所有汉字添加拼音 ruby。');
    }
    if (langTarget.isNotEmpty) {
      rules.add('textTranslation 使用 '+langTarget+'，提供完整句子译文。');
      rules.add('grammarNote 使用 '+langTarget+'，格式：【<语法>】：语法解释。');
    } else {
      rules.add('自动识别最合适的译文语言，并提供完整句子译文。');
      rules.add('grammarNote 使用译文语言，格式：【<语法>】：语法解释。');
    }

    final uri = Uri.parse(_normalizeEndpoint(endpoint, path: '/chat/completions'));
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $apiKey',
    };

    final ts = DateTime.now();
    int done = 0;
    final List<ExampleSentence> result = [];

    Future<void> worker(int index, String sense) async {
      final user = '原词：'+prompt+
          '。当前词义索引：' + index.toString() + '，词义内容：' + sense + '。'
          + rules.join(' ')+
          ' 请严格仅返回一个 JSON 对象，包含 senseIndex（'+index.toString()+'）、textPlain、textHtml、textTranslation、grammarNote。'
          ' 要求：基于该词义设定语境；textTranslation 与该词义保持一致；textPlain 简洁自然；'
          ' textHtml 在整句范围对所有汉字提供 ruby（根据语言选择假名或拼音），允许一个 ruby 中包含多组 <rb>/<rt>；'
          ' 并提供 grammarNote（译文语言），格式为【<语法>】：语法解释。';

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
      final objJson = _extractJsonObject(content);
      if (objJson == null) {
        throw Exception('AI response does not contain a valid JSON object');
      }
      final item = jsonDecode(objJson) as Map<String, dynamic>;
      result.add(ExampleSentence(
        id: null,
        wordId: 0,
        senseIndex: index,
        textPlain: (item['textPlain'] ?? '').toString(),
        textHtml: (item['textHtml'] ?? '').toString(),
        textTranslation: (item['textTranslation'] ?? '').toString(),
        grammarNote: (item['grammarNote'] ?? '').toString(),
        sourceModel: model,
        createdAt: ts,
        updatedAt: ts,
      ));

      done += 1;
      if (onProgress != null) onProgress(done, total);
    }

    // 并行度控制（分批 Future.wait）
    final concurrency = parallel <= 0 ? 1 : parallel;
    for (int start = 0; start < total; start += concurrency) {
      final end = (start + concurrency) > total ? total : (start + concurrency);
      final futures = <Future<void>>[];
      for (int i = start; i < end; i++) {
        futures.add(worker(i, senses[i]));
      }
      await Future.wait(futures);
    }

    // 按索引排序，保证结果稳定
    result.sort((a, b) => a.senseIndex.compareTo(b.senseIndex));
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

  // --- Language detection helpers ---
  String _detectSourceLanguageFromPrompt(String prompt) {
    final hasHiragana = RegExp(r'[\u3040-\u309F]').hasMatch(prompt);
    final hasKatakana = RegExp(r'[\u30A0-\u30FF]').hasMatch(prompt);
    final hasKanji = RegExp(r'[\u4E00-\u9FFF]').hasMatch(prompt);
    if (hasHiragana || hasKatakana || hasKanji) {
      return 'Japanese';
    }
    // If contains Chinese-only Han and typical Chinese punctuation, consider Chinese
    final chinesePunct = RegExp(r'[，。！？；：（）《》“”]');
    if (!hasHiragana && !hasKatakana && hasKanji && chinesePunct.hasMatch(prompt)) {
      return 'Chinese';
    }
    return 'English';
  }

  String _detectTargetLanguageFromAnswer(List<String> senses, String answer) {
    bool containsChinese(String s) => RegExp(r'[\u4E00-\u9FFF]').hasMatch(s);
    bool containsKana(String s) => RegExp(r'[\u3040-\u309F\u30A0-\u30FF]').hasMatch(s);

    if (containsChinese(answer) || senses.any(containsChinese)) {
      return 'Chinese';
    }
    if (senses.any(containsKana)) {
      // If meanings are in Japanese, default translation to English unless otherwise specified
      return 'English';
    }
    return 'English';
  }
}