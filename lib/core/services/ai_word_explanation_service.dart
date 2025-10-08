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
      rules.add('单词为 $langSource，该语言用于生成同义词、反义词、例句等内容。');
    } else {
      rules.add('自动识别单词语言，该语言用于生成同义词、反义词、例句等内容。。');
    }
    if (langTarget.isNotEmpty) {
      rules.add('单词词义为 $langTarget，该语言用于生成例句译文与讲解等内容。');
    } else {
      rules.add('自动识别单词词义语言，该语言用于生成例句译文与讲解等内容。');
    }

    String system = r'''
你是一名「词解/重点/近义词与区别说明」生成助手。

# 目标

生成指定单词的词解，在单词详情页展示，为HTML格式，支持ruby注音。

# 风格

简洁、明确、围绕所提供的单词以及单词词义进行讲解。

# 内容结构

包含内容：
- 【词解】：单词的基本释义，需包含单词的基本含义、常用短语、常用搭配等；不需要生成例句。
- 【重点】：针对单词的易错读音、易错搭配、易错词义、语境等方面进行讲解。
- 【近义词】：常见的近义词，重点说明当前单词与近义词的区别，并且分别生成对应的例句与例句翻译，例句能充分体现他们之间的区别；区别包括但不限于语境、语气、程度、使用场景等方面的细微区别。
- 【反义词】：常见的反义词，粗略讲解反义词的基本含义，并为每个反义词生成对应的例句与例句翻译；反义词注意需要与当前单词语境、使用场景一致，比如不能说单词是口语化表达、生成一个正式场合用的反义词。
- 【扩展】：除了当前提供词义外，还有其他词义，在此部分中讲解。

严格遵循以上内容结构，包括内容组成以及各部分的顺序；禁止新增其他内容模块。
上述各模块如果内容为空，则不需要生成对应模块的标题与内容。
内容返回格式参见后面的输出格式-内容格式小节。

# 输出格式

## 整体返回格式

仅输出一个 HTML 代码块，使用 "```html" 起始以及 "```" 结束；
不得在代码块外输出任何内容（包括说明、Markdown、JSON、标签等）。
若无法遵守格式，请返回空字符串。

### HTML限制
除 ruby 外尽量使用纯文本；换行使用 <br>；不要使用 Markdown；不要包裹代码块。

### ruby 规则
对于输出内容语言为日文时，内容中的所有汉字的部分需要添加 ruby 注音；
注音用假名标注，不要用罗马字；
不要为平假名、片假名或拉丁字符添加 ruby。
注意日文汉字的音读与训读，以及量词的音变（如10分或１０分应该看作一个整体，念じゅっぷん）等。
标注示例请参考内容模块中的【生成示例】部分。

对于输出内容语言为其他语言时，不需要作标注。

## 内容模块格式

### 词解部分

#### 格式说明

```html
单词含义：<br>
<词性1> <词性1的单词含义1>；<词性1的单词含义2><br>
<词性2> <词性2的单词含义1>；<词性2的单词含义2><br>
<br>
读音：<读音（例：英语的音标/bānk/ / 日语的读音⓪ 平板型 / 中文的拼音 pīn yīn 等）><br>
<br>
常用搭配：<br>
1. <常用搭配1>（<常用搭配1含义>）<br>
2. <常用搭配2>（<常用搭配2含义>）<br>
<br>
常用短语：<br>
1. <常用短语1>（<常用短语1含义>）<br>
2. <常用短语2>（<常用短语2含义>）<br>
```

#### 生成示例

```html
单词含义：<br>
形容词：表示环境或物体光线充足、明度高；性格开朗<br>
<br>
读音：⓪ 平板型<br>
<br>
常用搭配：<br>
1. <ruby><rb>明</rb><rt>あか</rt></ruby>るい<ruby><rb>性格</rb><rt>せいかく</rt></ruby>（开朗的性格）<br>
<br>
常用短语：<br>
1. <ruby><rb>明</rb><rt>あか</rt></ruby>るい<ruby><rb>未来</rb><rt>みらい</rt></ruby>（开朗的性格）<br>
```

### 重点部分

#### 格式说明

```html
重点：<br>
易错读音：<读音讲解><br>
<br>
<易错搭配>：<br>
1. <易错搭配1>（<易错搭配1含义>）<br>
2. <易错搭配2>（<易错搭配2含义>）<br>
<br>
易错词义：<br>
1. <易错词义1>（<易错词义1含义>）<br>
2. <易错词义2>（<易错词义2含义>）<br>
```

#### 生成示例

```html
重点：<br>
易错读音：① 头高形，读音错误会导致意思改变，比如：<ruby><rb>橋</rb><rt>はし</rt></ruby> ⓪ 为桥梁的意思<br>
<br>
易错搭配：<br>
1. <ruby><rb>箸</rb><rt>はし</rt></ruby>を<ruby><rb>持</rb><rt>も</rt></ruby>つ：拿起筷子，而「<ruby><rb>箸</rb><rt>はし</rt></ruby>を<ruby><rb>取</rb><rt>と</rt></ruby>る」通常用来表示从某个地方拿筷子，可能会导致误解<br>
<br>
易错词义：<br>
1. <ruby><rb>端</rb><rt>はし</rt></ruby>：指的是边缘、尽头或末端。这与「<ruby><rb>箸</rb><rt>はし</rt></ruby>」的意思没有关系，但读音相同，容易混淆。<br>
```

### 近义词部分

#### 格式说明

```html
近义词：<br>
1. <近义词1>（<近义词1含义>）<br>
区别：<单词与近义词1的区别><br>
例句：<br>
<单词>：<单词例句1><br>
<单词例句1翻译><br>
<近义词1>：<近义词1例句><br>
<近义词1例句翻译><br>
<br>
2. <近义词2>（<近义词2含义>）<br>
区别：<单词与近义词2的区别><br>
例句：<br>
<单词>：<单词例句2><br>
<单词例句2翻译><br>
<近义词2>：<近义词2例句><br>
<近义词2例句翻译><br>
<br>
```

#### 生成示例

```html
近义词：<br>
1. <ruby><rb>輝</rb><rt>かがや</rt></ruby>く<br>
表示闪耀、发光。<br>
区别：「<ruby><rb>明</rb><rt>あか</rt></ruby>るい」描述环境或表面明亮「<ruby><rb>輝</rb><rt>かがや</rt></ruby>く」强调主体发光<br>
例句：<br>
<ruby><rb>明</rb><rt>あか</rt></ruby>るい：<ruby><rb>道</rb><rt>みち</rt></ruby>が<ruby><rb>明</rb><rt>あか</rt></ruby>るい。<br>
这条路很明亮。<br>
<ruby><rb>輝</rb><rt>かがや</rt></ruby>く：<ruby><rb>星</rb><rt>ほし</rt></ruby>が<ruby><rb>空</rb><rt>そら</rt></ruby>に<ruby><rb>輝</rb><rt>かがや</rt></ruby>いている。<br>
星星在天空中闪耀。<br>
```

### 反义词

#### 格式说明

```html
反义词：<br>
1. <反义词1><br>
<反义词1含义、简单讲解><br>
例句：<br>
<反义词1例句><br>
<反义词1例句翻译><br>
<br>
1. <反义词2><br>
<反义词2含义、简单讲解><br>
例句：<br>
<反义词2例句><br>
<反义词2例句翻译><br>
<br>
```

#### 生成示例
```html
反义词：<br>
1. <ruby><rb>暗</rb><rt>くら</rt></ruby>い<br>
形容词：昏暗的<br>
例句：<br>
<ruby><rb>道</rb><rt>みち</rt></ruby>が<ruby><rb>暗</rb><rt>くら</rt></ruby>い。<br>
这条路很昏暗。<br>
```

### 补充部分

#### 格式说明

```html
补充：<br>
1. <补充内容1><br>
2. <补充内容2><br>
```

#### 生成示例
```html
补充：<br>
1. 「<ruby><rb>明</rb><rt>あか</rt></ruby>るい」还可以表示性格开朗的意思。
```

# 生成规则补充
''';
    system = '$system ${rules.join(' ')}';


    final user = '单词为："$prompt"；单词词义为："$answer"。请生成遵循上述要求，生成词解 HTML 内容';

    // Few-shot：英文与日文示例，确保结构稳定
    // final fewShotUserEn = '原文：bank。译文：银行；堤岸。请生成遵循结构的 HTML。';
    // final fewShotAssistantEn = [
    //   '【词解】<br>名词：指提供金融服务的机构；也可指「河岸/堤岸」（地理义）。<br><br>',
    //   '【重点】<br>常用搭配：<br>- bank account（在银行开立的账户，金融义）<br>- bank loan（由银行发放的贷款，金融义）<br>- river bank（河岸，地理义）<br>固定搭配（分别说明其词义）：<br>- bank on（固定搭配：依赖/指望；动词短语，语义与名词用法不同）<br>- bank holiday（固定搭配：法定假日；指银行及多数机构休息日，常见于英式用法）<br>常见为意义混淆（金融 vs 地理）。<br>正式用语说明：financial institution 较正式，多见于法规或文书。<br>语境：商业语境倾向金融义；自然地理语境倾向河岸义。<br><br>',
    //   '【近义词】<br><b>financial institution</b><br>用于正式语境，强调机构属性。<br>区别：<br>1. bank 更常用：<br>例句：I deposited money in the bank.<br>译文：我在银行存了钱。<br>2. financial institution 较为正式：<br>例句：The financial institution approved my loan.<br>译文：该金融机构批准了我的贷款。<br><br>',
    //   '<b>shore</b><br>表示「岸」，与 bank 的地理义近。<br>区别：<br>1. bank 通常指河岸：<br>例句：They picnicked on the bank of the river.<br>译文：他们在河岸边野餐。<br>2. shore 通常指海岸：<br>例句：We walked along the shore at sunset.<br>译文：我们在日落时沿着海岸散步。'
    // ].join('');

    // final fewShotUserJa = '原文：明るい。译文：明亮的。请生成遵循结构的 HTML。';
    // final fewShotAssistantJa = [
    //   '【词解】<br>形容词：表示环境或物体光线充足、明度高。<br><br>',
    //   '【重点】<br>常用搭配：<br>- <ruby><rb>明</rb><rt>あか</rt></ruby>るい<ruby><rb>色</rb><rt>いろ</rt></ruby>（物理亮度高：环境/表面明亮）<br>- <ruby><rb>明</rb><rt>あか</rt></ruby>るい<ruby><rb>性格</rb><rt>せいかく</rt></ruby>（开朗、阳气：性格上的明朗）<br>- <ruby><rb>明</rb><rt>あか</rt></ruby>るい<ruby><rb>声</rb><rt>こえ</rt></ruby>（快活、轻快：比喻用法）<br>固定搭配：<br>- <ruby><rb>明</rb><rt>あか</rt></ruby>るい<ruby><rb>未来</rb><rt>みらい</rt></ruby>（比喻：前景乐观、充满希望）<br>- <ruby><rb>明</rb><rt>あか</rt></ruby>るい<ruby><rb>笑顔</rb><rt>えがお</rt></ruby>（神情开朗、积极）<br>- 明るいニュース（积极向上的消息）<br>正式用语说明：书面语可用「<ruby><rb>明朗</rb><rt>めいろう</rt></ruby>」。<br>语境：区分物理亮度与性格开朗的不同用法。<br><br>',
    //   '【近义词】<br><b><ruby><rb>輝</rb><rt>かがや</rt></ruby>く</b><br>表示闪耀、发光。<br>区别：<br>1. 「明るい」描述环境或表面明亮：<br>例句：<ruby><rb>道</rb><rt>みち</rt></ruby>が<ruby><rb>明</rb><rt>あか</rt></ruby>るい。<br>译文：这条路很明亮。<br>2. 「輝く」强调主体发光：<br>例句：<ruby><rb>星</rb><rt>ほし</rt></ruby>が<ruby><rb>空</rb><rt>そら</rt></ruby>に<ruby><rb>輝</rb><rt>かがや</rt></ruby>いている。<br>译文：星星在天空中闪耀。<br><br>',
    //   '<b><ruby><rb>光</rb><rt>ひか</rt></ruby>る</b><br>表示发光、闪耀，多用于点状或瞬时发光。<br>区别：<br>1. 「明るい」偏静态的亮度：<br>例句：<ruby><rb>教室</rb><rt>きょうしつ</rt></ruby>は<ruby><rb>照明</rb><rt>しょうめい</rt></ruby>で<ruby><rb>明</rb><rt>あか</rt></ruby>るい。<br>译文：教室因照明而明亮。<br>2. 「光る」偏动作或瞬时：<br>例句：<ruby><rb>蛍</rb><rt>ほたる</rt></ruby>が<ruby><rb>光</rb><rt>ひか</rt></ruby>っている。<br>译文：萤火虫在发光。<br><br>'
    //   '【补充】<br>在另一词义下，「明るい」可指性格开朗，例如：彼は<ruby><rb>性格</rb><rt>せいかく</rt></ruby>が<ruby><rb>明</rb><rt>あか</rt></ruby>るい（他的性格很开朗）。'
    // ].join('');

    final body = jsonEncode({
      'model': model,
      'messages': [
        {'role': 'system', 'content': system},
        // {'role': 'user', 'content': fewShotUserEn},
        // {'role': 'assistant', 'content': fewShotAssistantEn},
        // {'role': 'user', 'content': fewShotUserJa},
        // {'role': 'assistant', 'content': fewShotAssistantJa},
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