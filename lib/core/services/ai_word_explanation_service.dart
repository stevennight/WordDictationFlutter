import 'dart:convert';
import 'package:http/http.dart' as http;

import 'config_service.dart';

class AIWordExplanationService {
  static AIWordExplanationService? _instance;
  final ConfigService _configService;

  AIWordExplanationService._(this._configService);

  static Future<AIWordExplanationService> getInstance() async {
    _instance ??= AIWordExplanationService._(await ConfigService.getInstance());
    return _instance!;
  }

  /// 生成词解HTML：包含【词解】【重点】【近义词】三个部分（若无则省略对应部分）
  /// - 同义词含多个项，每个项包含简述与区别说明，区别需配合例句；
  /// - 日文例句使用 ruby；否则不使用任何HTML标签（纯文本）；
  /// - 返回值：严格仅返回一个 HTML 字符串，不含 Markdown 或额外解释。
  Future<String> generateExplanationHtml({
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

    final langSource = (sourceLanguage?.trim().isNotEmpty ?? false) ? sourceLanguage!.trim() : '';
    final langTarget = (targetLanguage?.trim().isNotEmpty ?? false) ? targetLanguage!.trim() : '';

    final List<String> rules = [];
    if (langSource.isNotEmpty) {
      rules.add('原文（含同义词例句的 textPlain/textHtml）统一使用 '+langSource+'。');
    } else {
      rules.add('自动识别原文语言用于同义词例句的 textPlain/textHtml。');
    }
    if (langTarget.isNotEmpty) {
      rules.add('如需译文，统一使用 '+langTarget+'。');
    } else {
      rules.add('译文语言自动识别。');
    }

    final system = [
      '你是一名「词解/注意点/近义词与区别说明」生成助手。',
      '目标：生成适用于词条详情页的 HTML（为支持日文 ruby）。',
      '风格：简洁、明确、围绕当前译文进行讲解。',
      '结构要求：严格使用以下文本标题开始各段，若内容为空则省略该段：',
      '【词解】、【重点】、【近义词】、【补充】。',
      '近义词，如完全可互换则省略区别；如有细微区别也需说明',
      'HTML限制：除 ruby 外尽量使用纯文本；换行使用 <br>；不要使用 Markdown；不要包裹代码块。',
      'ruby 规则：仅在日文例句中为汉字添加 ruby，使用 <ruby><rb>漢字</rb><rt>かな</rt></ruby>；不要为假名或拉丁字符添加 ruby。',
      '如果除了当前词义，还有其他词义，需在【补充】中简单提及。',
      ...rules,
    ].join(' ');

    final user = '原文：'+prompt+'。译文：'+answer+'。请生成遵循上述结构与格式的 HTML。';

    // Few-shot：英文与日文示例，确保结构稳定
    final fewShotUserEn = '原文：bank。译文：银行；堤岸。请生成遵循结构的 HTML。';
    final fewShotAssistantEn = [
      '【词解】<br>名词：指提供金融服务的机构。也可指「河岸/堤岸」。在「堤岸」这一译文下的讲解侧重地理义。<br><br>',
      '【重点】<br>与「岸边」相关的含义不常见于商业语境，注意区分。<br><br>',
      '【近义词】<br><b>financial institution</b><br>用于正式语境，强调机构属性。<br>区别：<br>1. bank 更常用：例句：I deposited money in the bank.<br>2. financial institution 较为正式：例句：The financial institution approved my loan.<br><br>',
      '<b>shore</b><br>表示「岸」，与 bank 的地理义近。<br>区别：<br>1. bank 通常指河岸：例句：They picnicked on the bank of the river.<br>2. shore 通常指海岸：例句：We walked along the shore at sunset.'
    ].join('');

    final fewShotUserJa = '原文：明るい。译文：明亮的。请生成遵循结构的 HTML。';
    final fewShotAssistantJa = [
      '【词解】<br>形容词：表示环境或物体光线充足、明度高。<br>例句：この<ruby><rb>部屋</rb><rt>へや</rt></ruby>はとても<ruby><rb>明</rb><rt>あか</rt></ruby>るい。<br><br>',
      '【重点】<br>用于物理亮度语境；与自身发光的「<ruby><rb>輝</rb><rt>かがや</rt></ruby>く」区分，后者强调主体发光。<br><br>',
      '【近义词】<br><b><ruby><rb>輝</rb><rt>かがや</rt></ruby>く</b><br>表示闪耀、发光。<br>区别：<br>1. 「明るい」描述环境或表面明亮：例句：<ruby><rb>道</rb><rt>みち</rt></ruby>が<ruby><rb>明</rb><rt>あか</rt></ruby>るい。<br>2. 「輝く」强调主体发光：例句：<ruby><rb>星</rb><rt>ほし</rt></ruby>が<ruby><rb>空</rb><rt>そら</rt></ruby>に<ruby><rb>輝</rb><rt>かがや</rt></ruby>いている。<br><br>',
      '<b><ruby><rb>光</rb><rt>ひか</rt></ruby>る</b><br>表示发光、闪耀，多用于点状或瞬时发光。<br>区别：<br>1. 「明るい」偏静态的亮度：例句：<ruby><rb>教室</rb><rt>きょうしつ</rt></ruby>は<ruby><rb>照明</rb><rt>しょうめい</rt></ruby>で<ruby><rb>明</rb><rt>あか</rt></ruby>るい。<br>2. 「光る」偏动作或瞬时：例句：<ruby><rb>蛍</rb><rt>ほたる</rt></ruby>が<ruby><rb>光</rb><rt>ひか</rt></ruby>っている。<br><br>',
      '【补充】<br>在另一词义下，「明るい」可指性格开朗（例：彼は<ruby><rb>性格</rb><rt>せいかく</rt></ruby>が<ruby><rb>明</rb><rt>あか</rt></ruby>るい）。'
    ].join('');

    final body = jsonEncode({
      'model': model,
      'messages': [
        {'role': 'system', 'content': system},
        {'role': 'user', 'content': fewShotUserEn},
        {'role': 'assistant', 'content': fewShotAssistantEn},
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

    // 移除包裹的 Markdown 代码块或多余文本，提取纯 HTML
    final html = _extractHtml(content).trim();
    return html;
  }

  String _normalizeEndpoint(String endpoint, {required String path}) {
    final base = endpoint.endsWith('/') ? endpoint.substring(0, endpoint.length - 1) : endpoint;
    return '$base$path';
  }

  String _extractHtml(String content) {
    // 常见情况：```html ... ``` 或 ``` ... ``` 包裹
    final fenced = RegExp(r"```(?:html)?\s*([\s\S]*?)```", multiLine: true);
    final m = fenced.firstMatch(content);
    if (m != null) {
      return m.group(1) ?? '';
    }
    return content;
  }
}