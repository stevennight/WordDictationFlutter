import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'config_service.dart';
import '../models/dictionary.dart';
import 'dictionary_service.dart';
import 'dictionary_query_service.dart';
import 'package:flutter_word_dictation/shared/models/word.dart';

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
    List<String>? sourcesHtml,
    List<Map<String, String>>? sourcesMeta,
  }) async {
    return generateExplanationHtmlStructured(
      prompt: prompt,
      answer: answer,
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
      sourcesHtml: sourcesHtml,
      sourcesMeta: sourcesMeta,
    );
  }

  Future<Map<String, dynamic>> normalizeWord({
    required String prompt,
    String? sourceLanguage,
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
    final system = r'''你是一名词条归一化助手。

目标：判断输入单词的语言并进行最小必要的标准化；仅在日文时返回“汉字写法”和“假名写法”两个规范形。

输出要求：
- 严格只返回一个 JSON 对象；不得包含任何解释、Markdown、额外文本或多余字段；
- 统一键名：
  - 当语言为日文：{"language":"ja","jaKanji":"…","jaKana":"…"}
  - 当语言为其他：{"language":"xx","promptNormalized":"…"}（xx 为ISO或通用语言标记）
- 当无法判断语言，返回 {"language":"","promptNormalized":"原文"}

归一化规则：
- 日文：
  - jaKanji：常见标准汉字写法（若为外来语或本无汉字写法，填空字符串）
  - jaKana：常见标准假名写法（平假名或片假名，优先教材或通行用法）
  - 不要返回罗马字；不要混合假名与拉丁字符；
- 非日文：
  - promptNormalized 为原文或最常见标准写法（如大小写规范、去除多余空格、常见变体的主形）
  - 不要创造新词或合成词；
''';
    final user = '输入："'+prompt+'"。请按上面的 JSON 规范返回。';
    final body = jsonEncode({
      'model': model,
      'messages': [
        {'role': 'system', 'content': system},
        {'role': 'user', 'content': user},
      ],
      'temperature': temperature,
    });
    final resp = await http.post(uri, headers: headers, body: body);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      return {
        'language': '',
        'promptNormalized': prompt,
      };
    }
    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    final content = decoded['choices']?[0]?['message']?['content'] as String? ?? '';
    final objStr = _extractJsonObject(content);
    if (objStr == null || objStr.isEmpty) {
      return {
        'language': '',
        'promptNormalized': prompt,
      };
    }
    try {
      final data = jsonDecode(objStr) as Map<String, dynamic>;
      return data;
    } catch (_) {
      return {
        'language': '',
        'promptNormalized': prompt,
      };
    }
  }

  Future<Map<String, dynamic>> pickBestDictionaryEntries({
    required String prompt,
    required String answer,
    required Map<String, List<Map<String, String>>> entries,
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
    final system = r'''你是一名词典候选项选择器。

任务：在每个词典的候选条目中，选择与给定「单词（prompt）」「词义（answer）」最匹配的一项；若无合适项则返回 null。

输入（user为JSON）：{"prompt":"…","answer":"…","entries":{"dictId":[{"key":"…","html":"…"},…]}}

匹配准则（按重要性排序）：
1. 释义一致性：候选HTML中的释义与 answer 高度一致；避免跨义项；
2. 用法可信度：词性、常用搭配/短语、语境与 answer 一致或相容；
3. 词形与范围：候选 key 与 prompt/归一化形态相符；避免过宽或过窄的条目（如仅短语或过泛条目）；
4. 质量优先：若多个候选合理，选择信息更完整、结构更规范者；
5. 排除：若候选HTML明显指向不同词义、缩略、同形异义或仅为跳转/索引，判定为不合适。

输出：
- 严格只返回一个 JSON 对象：{ "dictId": "chosenKey" | null, … }
- dictId 为输入 entries 的键；chosenKey 必须取自对应候选的 key；无合适项时填 null；
- 不得包含除该对象外的任何内容（禁止解释、Markdown、文本）。
''';
    final payload = jsonEncode({
      'prompt': prompt,
      'answer': answer,
      'entries': entries,
    });
    final user = payload;
    final body = jsonEncode({
      'model': model,
      'messages': [
        {'role': 'system', 'content': system},
        {'role': 'user', 'content': user},
      ],
      'temperature': temperature,
      'response_format': {'type': 'json_object'},
    });
    final resp = await http.post(uri, headers: headers, body: body);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      return {};
    }
    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    final content = decoded['choices']?[0]?['message']?['content'] as String? ?? '';
    debugPrint('[AISelect][content] ' + content);
    final objStr = _extractJsonObject(content);
    debugPrint('[AISelect][json_str] ' + (objStr ?? ''));
    if (objStr == null || objStr.isEmpty) return {};
    try {
      final data = jsonDecode(objStr) as Map<String, dynamic>;
      final total = data.length;
      int matched = 0;
      data.forEach((k, v) {
        final s = (v is String) ? v.trim() : '';
        if (s.isNotEmpty) matched++;
      });
      debugPrint('[AISelect] 自动选择结果：词典总数=' + total.toString() + '，命中数=' + matched.toString());
      try {
        final pretty = const JsonEncoder.withIndent('  ').convert(data);
        debugPrint('[AISelect][json_pretty]\n' + pretty);
      } catch (_) {}
      return data;
    } catch (_) {
      return {};
    }
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

  String? _extractJsonObject(String content) {
    final start = content.indexOf('{');
    final end = content.lastIndexOf('}');
    if (start >= 0 && end > start) {
      return content.substring(start, end + 1);
    }
    return null;
  }

  Future<String> generateExplanationHtmlStructured({
    required String prompt,
    required String answer,
    String? sourceLanguage,
    String? targetLanguage,
    List<String>? sourcesHtml,
    List<Map<String, String>>? sourcesMeta,
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
      rules.add('textHtml/textPlain 中的例句、搭配等使用 ' + langSource + '。');
    } else {
      rules.add('自动识别单词语言，用于生成例句、搭配等内容。');
    }
    if (langTarget.isNotEmpty) {
      rules.add('除少量原文引用（「…」）外，所有 textHtml 内容均使用 ' + langTarget + '。');
    } else {
      rules.add('自动识别词义语言；除少量原文引用（「…」）外，所有 textHtml 内容均使用该语言。');
    }

    final system = r'''
只返回一个 JSON 对象，严禁输出除 JSON 外的任何内容；禁止使用 Markdown 代码块或 ```json 包裹。

格式要求：
- 严格合法 JSON（UTF-8，键用双引号，字符串用双引号，数组/对象无尾逗号）。
- 不输出解释、Markdown、示例或额外文本。
- 所有字符串去除首尾空白。
- 对不可确定的内容，省略该字段或返回空数组；不要返回 null。

字段定义：
definition
- senses: 数组，相同词性但是意思不同的情况下分为多个子项。每项对象：
  - pos: 词性标签，必须从对应语言的枚举列表中选择，使用译文语言描述（中文/英文/日文）。
  - text: 该义项的简洁释义。
- pronunciation: 对象，可省略
  - text: 发音（英语用 IPA；日语用假名，并且在假名后⓪、①、②…的形式标识声调；中文用拼音；其他根据具体语言返回对应的发音标注）。
- collocations: 数组，0–5项，尽可能多，但要注意为常用搭配、组合此、熟语、谚语，不要随便组合词语或短语（比如コンビニでアルバイトする这种是禁止出现的）。每项对象：
  - textHtml: 搭配/熟语（原文语言；允许 ruby）。

highlights
- 数组，0–3项，尽可能多。每项对象：
  - textHtml: 易错点/注意点说明（译文语言；允许在「…」中引述少量原文并可带 ruby）。

synonyms
- 数组，0–3项，尽可能多。每项对象：
  - termPlain: 近义词词形
  - termHtml: 近义词词形（含 ruby 的版本）。
  - gloss: 近义词简要含义。
  - differenceHtml: 与当前词的区别（译文语言；允许在「…」中引述少量原文并可带 ruby）。
  - selfHtml: 使用当前词的例句（原文语言；允许 ruby）。
  - selfTranslation: 上述例句译文。
  - synHtml: 使用近义词的例句（原文语言；允许 ruby）。
  - synTranslation: 上述例句译文。

antonyms
- 数组，0–2项，尽可能多。每项对象：
  - termPlain: 反义词词形（Html 可含 ruby）
  - termHtml: 反义词词形（含 ruby 的版本）。
  - gloss: 反义词简要含义。
  - exampleHtml: 使用反义词的例句（原文语言；允许 ruby）。
  - exampleTranslation: 上述例句译文。

extras
- 数组，0–3项，尽可能多。每项对象：
  - textHtml: 与该词相关的简短补充说明（译文语言；允许在「…」中引述少量原文并可带 ruby）。

ruby 规则：
- 仅在“日文内容”中为含汉字的词整体标注 ruby。
- 平假名、片假名、中文等其他字符禁止标注ruby。
- 不拆词逐字标注；保持 <ruby><rb>词</rb><rt>假名</rt></ruby> 结构。
- ruby 格式：<ruby><rb>…</rb><rt>…</rt></ruby>。
- 没有需要 ruby 标注的内容时，则与 plain 内容没有任何区别。
 - 若原文语言非日文，则禁止任何 ruby 标注（包括译文与引用）。

词性枚举（pos 取值必须来自以下列表）：
- zh（中文）：名词、动词、形容词、副词、介词、连词、代词、数词、量词、叹词、助词
- en（英文）：noun、verb、adjective、adverb、preposition、conjunction、pronoun、numeral、determiner、interjection、auxiliary
- ja（日文）：名词、动词、形容词、形容动词、副词、連体詞、接続詞、感動詞、助詞、助動詞
- other（其他）：noun、verb、adjective、adverb、pronoun、preposition、conjunction、interjection、determiner、particle、auxiliary、classifier

生成约束：
- 例句尽可能使用一些高级用法，以便用户复习语法内容。
- 严格依据提供的单词（prompt）与词义（answer）。
- 生成的内容尽可能完善，不遗漏任何重要信息。
''';

    final refs = (sourcesHtml ?? const <String>[]).where((e) => e.trim().isNotEmpty).toList();
    final refsJoined = () {
      if (refs.isEmpty) return '';
      final truncated = refs.map((e) {
        final t = e.trim();
        return t.length > 4000 ? t.substring(0, 4000) : t;
      }).toList();
      return '参考词典原始HTML：\n' + truncated.join('\n\n---\n\n');
    }();
    final metas = (sourcesMeta ?? const <Map<String, String>>[])
        .where((m) => (m['dictionary']?.trim().isNotEmpty ?? false) && (m['key']?.trim().isNotEmpty ?? false))
        .toList();

    final user = '单词为："' + prompt + '"；单词词义为："' + answer + '"。请按上述JSON结构返回内容，只返回一个JSON对象。';

    final body = jsonEncode({
      'model': model,
      'messages': [
        {'role': 'system', 'content': system},
        if (refsJoined.isNotEmpty) {'role': 'user', 'content': refsJoined},
        {'role': 'system', 'content': rules.join(' ')},
        {'role': 'user', 'content': user},
      ],
      'temperature': temperature,
      'top_p': 1,
      'response_format': {'type': 'json_object'},
    });

    final resp = await http.post(uri, headers: headers, body: body);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('AI request failed: ${resp.statusCode} ${resp.body}');
    }

    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    final content = decoded['choices']?[0]?['message']?['content'] as String? ?? '';
    debugPrint('[AIExplain][content] ' + content);
    final objStr = _extractJsonObject(content) ?? '';
    debugPrint('[AIExplain][json_str] ' + objStr);
    if (objStr.isEmpty) return '';
    dynamic root;
    try {
      root = jsonDecode(objStr);
    } catch (_) {
      return '';
    }
    final data = _asMapSD(root);
    try {
      final pretty = const JsonEncoder.withIndent('  ').convert(data);
      debugPrint('[AIExplain][json_pretty]\n' + pretty);
    } catch (_) {}
    final html = _renderExplanationHtmlFromJson(data, metas, prompt: prompt, answer: answer, sourceLanguage: langSource);
    return html;
  }

  String _renderExplanationHtmlFromJson(Map<String, dynamic> data, List<Map<String, String>> metas, {required String prompt, required String answer, String? sourceLanguage}) {
    final src = (sourceLanguage ?? '').trim().toLowerCase();
    final sourceIsJa = src == 'ja' || src == 'jp' || src == 'japanese';
    String _cleanRubyKana(String html, {bool translation = false, bool allowQuoted = true, bool sourceJa = false}) {
      if (html.trim().isEmpty) return html;
      String out = html;
      final regRuby = RegExp(r"<ruby>([\s\S]*?)<\/ruby>", multiLine: true);
      out = out.replaceAllMapped(regRuby, (m) {
        final block = m.group(1) ?? '';
        final rbMatch = RegExp(r"<rb>([\s\S]*?)<\/rb>").firstMatch(block);
        final rtMatch = RegExp(r"<rt>([\s\S]*?)<\/rt>").firstMatch(block);
        final rb = rbMatch == null ? '' : (rbMatch.group(1) ?? '');
        final rt = rtMatch == null ? '' : (rtMatch.group(1) ?? '');
        final hasHan = RegExp(r"[\u4E00-\u9FFF]").hasMatch(rb);
        final isKanaRt = RegExp(r"^[\u3041-\u3096\u30A1-\u30FA\u30FC\u30FB\u30F4\u30F7-\u30FA]+$").hasMatch(rt);
        if (!sourceJa && isKanaRt) {
          return rb;
        }
        bool inQuoted = false;
        if (translation) {
          final before = out.substring(0, m.start);
          final after = out.substring(m.end);
          final pairs = [
            ['「', '」'],
            ['『', '』'],
            ['《', '》'],
            ['〈', '〉'],
            ['【', '】'],
            ['（', '）'],
            ['(', ')'],
            ['“', '”'],
            ['‘', '’'],
            ['"', '"'],
            ['\'', '\''],
          ];
          for (final p in pairs) {
            final o = before.lastIndexOf(p[0]);
            final c = after.indexOf(p[1]);
            if (o >= 0 && c >= 0) {
              inQuoted = true;
              break;
            }
          }
        }
        final keep = sourceJa && hasHan && isKanaRt && (!translation || (allowQuoted && inQuoted));
        if (!keep) {
          return rb;
        }
        return m.group(0) ?? '';
      });
      return out;
    }
    String textOrHtml(Map<String, dynamic> obj, {bool translation = false, bool allowQuoted = true}) {
      final h0 = _asString(obj['textHtml']);
      final h = _cleanRubyKana(h0, translation: translation, allowQuoted: allowQuoted, sourceJa: sourceIsJa);
      return h;
    }
    final sb = StringBuffer();
    var def = _asMapSD(data['definition']);
    var senses = _asListD(def['senses']);
    var pron = _asMapSD(def['pronunciation']);
    var collos = _asListD(def['collocations']);
    if (senses.isEmpty && collos.isEmpty && pron.isEmpty) {
      def = _asMapSD(data);
      senses = _asListD(def['senses']);
      pron = _asMapSD(def['pronunciation']);
      collos = _asListD(def['collocations']);
    }
    if (senses.isNotEmpty || collos.isNotEmpty || pron.isNotEmpty) {
      sb.write('单词含义：<br>');
      for (final s in senses) {
        final m = _asMapSD(s);
        final pos = _asString(m['pos']);
        final text = _asString(m['text']);
        if (pos.trim().isNotEmpty || text.trim().isNotEmpty) {
          sb.write((pos.trim().isNotEmpty ? pos + '：' : '') + text + '<br>');
        }
      }
      var pronText = _asString(pron['text']);
      var accent = _asString(pron['accent']);
      if (accent.trim().isEmpty && pronText.trim().isNotEmpty) {
        final m = RegExp(r'^(.*?)[\s]*(⓪|①|②|③|④|⑤|⑥|⑦|⑧|⑨|⑩|[0-9]+)$').firstMatch(pronText);
        if (m != null) {
          pronText = (m.group(1) ?? '').trim();
          accent = (m.group(2) ?? '').trim();
        }
      }
      if (pronText.trim().isNotEmpty) sb.write('读音：' + pronText + '<br>');
      if (accent.trim().isNotEmpty) sb.write('声调：' + accent + '<br>');
      if (collos.isNotEmpty) {
        sb.write('常用搭配/熟语：<br>');
        int idx = 1;
        for (final c in collos) {
          final t = textOrHtml(_asMapSD(c), translation: false, allowQuoted: true);
          if (t.trim().isEmpty) continue;
          sb.write(idx.toString() + '. ' + t + '<br>');
          idx++;
        }
      }
      sb.write('<br>');
    } else {
      final fallback = answer.trim();
      if (fallback.isNotEmpty) {
        sb.write('词解：<br>');
        sb.write(fallback + '<br><br>');
      }
    }

    final highs = _asListD(data['highlights']);
    if (highs.isNotEmpty) {
      sb.write('重点：<br>');
      int idx = 1;
      for (final h in highs) {
        final hm = _asMapSD(h);
        final tHtml = _cleanRubyKana(_asString(hm['textHtml']), translation: true, allowQuoted: true, sourceJa: sourceIsJa);
        final t = tHtml;
        if (t.trim().isEmpty) continue;
        sb.write(idx.toString() + '. ' + t + '<br>');
        idx++;
      }
      sb.write('<br>');
    }

    final syns = _asListD(data['synonyms']);
    if (syns.isNotEmpty) {
      sb.write('近义词：<br>');
      int idx = 1;
      for (final s in syns) {
        final m = _asMapSD(s);
        final termHtml = _cleanRubyKana(_asString(m['termHtml']), sourceJa: sourceIsJa);
        final termPlain = _asString(m['termPlain']);
        final term = termHtml.trim().isNotEmpty ? termHtml : termPlain;
        final gloss = _asString(m['gloss']);
        final diff = _cleanRubyKana(_asString(m['differenceHtml']), translation: true, sourceJa: sourceIsJa);
        final sp = _asString(m['selfPlain']);
        final sh = _cleanRubyKana(_asString(m['selfHtml']), translation: false, sourceJa: sourceIsJa);
        final st = _asString(m['selfTranslation']);
        final yp = _asString(m['synPlain']);
        final yh = _cleanRubyKana(_asString(m['synHtml']), translation: false, sourceJa: sourceIsJa);
        final yt = _asString(m['synTranslation']);
        sb.write(idx.toString() + '. ' + term + (gloss.trim().isNotEmpty ? '（' + gloss + '）' : '') + '<br>');
        if (diff.trim().isNotEmpty) sb.write('区别：' + diff + '<br>');
        if (sp.trim().isNotEmpty || sh.trim().isNotEmpty || yp.trim().isNotEmpty || yh.trim().isNotEmpty) {
          sb.write('例句：<br>');
          final selfLine = (sh.trim().isNotEmpty ? sh : sp);
          if (selfLine.trim().isNotEmpty) sb.write(selfLine + '<br>');
          if (st.trim().isNotEmpty) sb.write(st + '<br>');
          final synLine = (yh.trim().isNotEmpty ? yh : yp);
          if (synLine.trim().isNotEmpty) sb.write(synLine + '<br>');
          if (yt.trim().isNotEmpty) sb.write(yt + '<br>');
        }
        idx++;
      }
      sb.write('<br>');
    }

    final ants = _asListD(data['antonyms']);
    if (ants.isNotEmpty) {
      sb.write('反义词：<br>');
      int idx = 1;
      for (final a in ants) {
        final m = _asMapSD(a);
        final termHtml = _cleanRubyKana(_asString(m['termHtml']), sourceJa: sourceIsJa);
        final termPlain = _asString(m['termPlain']);
        final term = termHtml.trim().isNotEmpty ? termHtml : termPlain;
        final gloss = _asString(m['gloss']);
        sb.write(idx.toString() + '. ' + term + '<br>');
        if (gloss.trim().isNotEmpty) sb.write(gloss + '<br>');
        final ep = _asString(m['examplePlain']);
        final eh = _cleanRubyKana(_asString(m['exampleHtml']), sourceJa: sourceIsJa);
        final et = _asString(m['exampleTranslation']);
        final line = (eh.trim().isNotEmpty ? eh : ep);
        if (line.trim().isNotEmpty) sb.write('例句：' + line + '<br>');
        if (et.trim().isNotEmpty) sb.write(et + '<br>');
        idx++;
      }
      sb.write('<br>');
    }

    final extras = _asListD(data['extras']);
    if (extras.isNotEmpty) {
      sb.write('扩展：<br>');
      int idx = 1;
      for (final e in extras) {
        final t = textOrHtml(_asMapSD(e), translation: true, allowQuoted: true);
        if (t.trim().isEmpty) continue;
        sb.write(idx.toString() + '. ' + t + '<br>');
        idx++;
      }
      sb.write('<br>');
    }

    if (metas.isNotEmpty) {
      sb.write('参考来源：<br>');
      int idx = 1;
      for (final m in metas) {
        final dn = (m['dictionary'] ?? '').trim();
        final k = (m['key'] ?? '').trim();
        if (dn.isEmpty && k.isEmpty) continue;
        sb.write(idx.toString() + '. 词典：' + dn + '；条目：' + k + '<br>');
        idx++;
      }
    }

    final s = sb.toString().trim();
    return s;
  }

  Map<String, dynamic> _asMapSD(dynamic v) {
    if (v is Map) {
      final Map<String, dynamic> m = {};
      v.forEach((key, value) {
        m[key.toString()] = value;
      });
      return m;
    }
    return <String, dynamic>{};
  }

  List<dynamic> _asListD(dynamic v) {
    if (v is List) {
      return List<dynamic>.from(v);
    }
    return const <dynamic>[];
  }

  String _asString(dynamic v) {
    if (v == null) return '';
    if (v is String) return v;
    return v.toString();
  }
}
extension AIWordExplanationSourceExt on AIWordExplanationService {
  Future<(List<String>, List<Map<String, String>>)> collectSourcesForWord(Word word) async {
    final ds = DictionaryService();
    final dq = DictionaryQueryService();
    final dicts = await ds.getDictionaries();
    final norm = await normalizeWord(prompt: word.prompt);
    final lang = (norm['language'] ?? '') as String;
    final terms = <String>{};
    if (lang == 'ja') {
      final k1 = (norm['jaKanji'] ?? '') as String;
      final k2 = (norm['jaKana'] ?? '') as String;
      if (k1.trim().isNotEmpty) terms.add(k1.trim());
      if (k2.trim().isNotEmpty) terms.add(k2.trim());
    } else {
      final t = (norm['promptNormalized'] ?? word.prompt) as String;
      terms.add(t.trim().isNotEmpty ? t.trim() : word.prompt);
    }

    final Map<String, List<Map<String, String>>> entries = {};
    for (final d in dicts) {
      final List<Map<String, String>> list = [];
      for (final t in terms) {
        final keys = await dq.searchKeys(d, t, limit: 32);
        for (final k in keys) {
          final html0 = await dq.lookupWord(d, k);
          final h = (html0 ?? '').trim();
          if (h.isNotEmpty && _htmlMatchesTerms(h, terms)) {
            final trunc = h.length > 2000 ? h.substring(0, 2000) : h;
            list.add({'key': k, 'html': trunc});
          }
        }
      }
      if (list.isEmpty) {
        for (final t in terms) {
          final keys = await dq.searchKeys(d, t, limit: 8);
          for (final k in keys) {
            final html0 = await dq.lookupWord(d, k);
            final h = (html0 ?? '').trim();
            if (h.isNotEmpty) {
              final trunc = h.length > 2000 ? h.substring(0, 2000) : h;
              list.add({'key': k, 'html': trunc});
            }
          }
          if (list.isNotEmpty) break;
        }
      }
      if (list.isNotEmpty) {
        entries[d.path] = list;
      }
    }
    final picks = await pickBestDictionaryEntries(prompt: word.prompt, answer: word.answer, entries: entries);
    final htmls = <String>[];
    final metas = <Map<String, String>>[];
    for (final dp in entries.keys) {
      String chosen = '';
      final fromAI = picks[dp];
      if (fromAI is String && fromAI.trim().isNotEmpty) {
        chosen = fromAI.trim();
      } else {
        final list = entries[dp] ?? const <Map<String, String>>[];
        if (list.isNotEmpty) {
          final first = list.first;
          chosen = (first['key'] ?? '').trim();
        }
      }
      if (chosen.isEmpty) continue;
      Dictionary? dict;
      for (final d in dicts) {
        if (d.path == dp) {
          dict = d;
          break;
        }
      }
      if (dict == null) continue;
      final h = await dq.lookupWord(dict, chosen);
      final hh = (h ?? '').trim();
      if (hh.isNotEmpty) {
        htmls.add(hh);
        metas.add({'dictionary': dict.name, 'key': chosen});
      }
    }
    dq.dispose();
    return (htmls, metas);
  }

  bool _htmlMatchesTerms(String html, Set<String> terms) {
    final variants = <String>{};
    for (final t in terms) {
      final s = t.trim();
      if (s.isEmpty) continue;
      variants.add(s);
      variants.add(s.replaceAll('‐', '').replaceAll('‑', '').replaceAll('–', '').replaceAll('—', '').replaceAll('-', ''));
      variants.add(s.replaceAll('‐', '・').replaceAll('‑', '・').replaceAll('–', '・').replaceAll('—', '・').replaceAll('-', '・'));
      variants.add(_toKatakana(s));
      variants.add(_toHiragana(s));
    }
    for (final v in variants) {
      if (v.isNotEmpty && html.contains(v)) return true;
    }
    return false;
  }

  String _toKatakana(String input) {
    final sb = StringBuffer();
    for (int i = 0; i < input.length; i++) {
      final code = input.codeUnitAt(i);
      if (code >= 0x3041 && code <= 0x3096) {
        sb.writeCharCode(code + 0x60);
      } else {
        sb.writeCharCode(code);
      }
    }
    return sb.toString();
  }

  String _toHiragana(String input) {
    final sb = StringBuffer();
    for (int i = 0; i < input.length; i++) {
      final code = input.codeUnitAt(i);
      if (code >= 0x30A1 && code <= 0x30FA) {
        sb.writeCharCode(code - 0x60);
      } else {
        sb.writeCharCode(code);
      }
    }
    return sb.toString();
  }
}
