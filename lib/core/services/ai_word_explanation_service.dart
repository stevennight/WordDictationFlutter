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
由于是教学内容，请确保内容的准确性，不需要包含任何个人偏好、情感色彩，不要画蛇添足。

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
多个内容模块之间，用 `<br><br>` 分隔。

### ruby 规则
对于输出内容语言为日文时，内容中的所有汉字的部分需要添加 ruby 注音；
注音用假名标注，不要用罗马字；
禁止为平假名、片假名或拉丁字符的单词添加注音ruby，但句子中的汉字仍要添加注音ruby。
注意日文汉字的音读与训读，以及量词的音变等。
标注示例请参考内容模块中的【生成示例】部分。
ruby生成时注意标签的闭合准确。

对于输出内容语言为其他语言时，不需要作标注。

## 内容模块格式

### 词解部分

#### 格式说明
```html
<!-- 存在多个词性、含义时按照格式生成多个 -->
单词含义：
<词性1> <词性1的单词含义1>；<词性1的单词含义2>
<词性2> <词性2的单词含义1>；<词性2的单词含义2>
读音：<读音（例：英语的音标 /bānk/ / 日语的读音 あかるい / 中文的拼音 pīn yīn 等）>
<!-- 如果是日语，需要标注声调 -->
声调：⓪
<!-- 存在多个常用搭配时按照格式生成多个，尽可能生成3-8个，但是要确保确实为常用搭配 -->
常用搭配：
1. <常用搭配1>（<常用搭配1含义>）
2. <常用搭配2>（<常用搭配2含义>）
<!-- 存在多个常用短语时按照格式生成多个，尽可能生成3-8个，但是要确保确实为常用短语 -->
常用短语：
1. <常用短语1>（<常用短语1含义>）
2. <常用短语2>（<常用短语2含义>）
```

#### 生成示例

```html
单词含义：
形容词：表示环境或物体光线充足、明度高；性格开朗
读音：あかるい
声调：⓪
常用搭配：
1. <ruby><rb>明</rb><rt>あか</rt></ruby>るい<ruby><rb>性格</rb><rt>せいかく</rt></ruby>（开朗的性格）
常用短语：
1. <ruby><rb>明</rb><rt>あか</rt></ruby>るい<ruby><rb>未来</rb><rt>みらい</rt></ruby>（开朗的性格）
```

### 重点部分

#### 格式说明

```html
重点：
易错读音：<读音讲解>
<!-- 存在多个易错搭配时按照格式生成多个 -->
易错搭配：
1. <易错搭配1>（<易错搭配1含义>）
2. <易错搭配2>（<易错搭配2含义>）
<!-- 存在多个易错词义时按照格式生成多个 -->
易错词义：
1. <易错词义1>（<易错词义1含义>）
2. <易错词义2>（<易错词义2含义>）
```

#### 生成示例

```html
重点：
易错读音：①，读音错误会导致意思改变，比如：<ruby><rb>橋</rb><rt>はし</rt></ruby> ⓪ 为桥梁的意思
易错搭配：
1. <ruby><rb>箸</rb><rt>はし</rt></ruby>を<ruby><rb>持</rb><rt>も</rt></ruby>つ：拿起筷子，而「<ruby><rb>箸</rb><rt>はし</rt></ruby>を<ruby><rb>取</rb><rt>と</rt></ruby>る」通常用来表示从某个地方拿筷子，可能会导致误解
易错词义：
1. <ruby><rb>端</rb><rt>はし</rt></ruby>：指的是边缘、尽头或末端。这与「<ruby><rb>箸</rb><rt>はし</rt></ruby>」的意思没有关系，但读音相同，容易混淆。
```

### 近义词部分

#### 格式说明

```html
<!-- 存在多个近义词时按照格式生成多个，尽可能生成3-5个，但是要确保确实为近义词 -->
近义词：
1. <近义词1>（<近义词1含义>）
区别：<单词与近义词1的区别>
例句：
<单词>：<单词例句1>
<单词例句1翻译>
<近义词1>：<近义词1例句>
<近义词1例句翻译>

2. <近义词2>（<近义词2含义>）
区别：<单词与近义词2的区别>
例句：
<单词>：<单词例句2>
<单词例句2翻译>
<近义词2>：<近义词2例句>
<近义词2例句翻译>

```

#### 生成示例

```html
近义词：
1. <ruby><rb>輝</rb><rt>かがや</rt></ruby>く
表示闪耀、发光。
区别：「<ruby><rb>明</rb><rt>あか</rt></ruby>るい」描述环境或表面明亮「<ruby><rb>輝</rb><rt>かがや</rt></ruby>く」强调主体发光
例句：
<ruby><rb>明</rb><rt>あか</rt></ruby>るい：<ruby><rb>道</rb><rt>みち</rt></ruby>が<ruby><rb>明</rb><rt>あか</rt></ruby>るい。
这条路很明亮。
<ruby><rb>輝</rb><rt>かがや</rt></ruby>く：<ruby><rb>星</rb><rt>ほし</rt></ruby>が<ruby><rb>空</rb><rt>そら</rt></ruby>に<ruby><rb>輝</rb><rt>かがや</rt></ruby>いている。
星星在天空中闪耀。
```

### 反义词

#### 格式说明

```html
<!-- 存在多个反义词时按照格式生成多个 -->
反义词：
1. <反义词1>
<反义词1含义、简单讲解>
例句：
<反义词1例句>
<反义词1例句翻译>

2. <反义词2>
<反义词2含义、简单讲解>
例句：
<反义词2例句>
<反义词2例句翻译>
```

#### 生成示例
```html
反义词：
1. <ruby><rb>暗</rb><rt>くら</rt></ruby>い
形容词：昏暗的
例句：
<ruby><rb>道</rb><rt>みち</rt></ruby>が<ruby><rb>暗</rb><rt>くら</rt></ruby>い。
这条路很昏暗。
```

### 补充部分

#### 格式说明

```html
补充：
1. <补充内容1>
2. <补充内容2>
```

#### 生成示例
```html
<!-- 存在多个补充内容时按照格式生成多个 -->
补充：
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

    const fewShotUserJa = '单词为："雨（あめ）①"；单词词义为："下雨，雨"。请生成遵循上述要求，生成词解 HTML 内容。';
    const fewShotAssistantJa = r'''
单词含义：
名词：下雨；雨；降雨
读音：あめ
声调：①
常用搭配：
1. <ruby><rb>雨</rb><rt>あめ</rt></ruby>が<ruby><rb>降</rb><rt>ふ</rt></ruby>る（下雨）
2. <ruby><rb>雨</rb><rt>あめ</rt></ruby>がやむ（雨停）
3. <ruby><rb>雨</rb><rt>あめ</rt></ruby>に<ruby><rb>濡</rb><rt>ぬ</rt></ruby>れる（被雨淋湿）
4. <ruby><rb>大雨</rb><rt>おおあめ</rt></ruby>／<ruby><rb>小雨</rb><rt>こさめ</rt></ruby>（大雨／小雨）
5. <ruby><rb>強</rb><rt>つよ</rt></ruby>い<ruby><rb>雨</rb><rt>あめ</rt></ruby>／<ruby><rb>弱</rb><rt>よわ</rt></ruby>い<ruby><rb>雨</rb><rt>あめ</rt></ruby>（雨势大／雨势小）
常用短语：
1. <ruby><rb>雨</rb><rt>あめ</rt></ruby>の<ruby><rb>日</rb><rt>ひ</rt></ruby>（下雨的日子）
2. <ruby><rb>雨上がり</rb><rt>あめあがり</rt></ruby>（雨后）
3. <ruby><rb>雨模様</rb><rt>あめもよう</rt></ruby>（看起来要下雨的样子）
4. <ruby><rb>雨宿り</rb><rt>あまやどり</rt></ruby>（避雨）
5. <ruby><rb>雨男</rb><rt>あめおとこ</rt></ruby>／<ruby><rb>雨女</rb><rt>あめおんな</rt></ruby>（常被调侃“自带雨”的人）<br><br>


重点：
易错读音：<ruby><rb>雨</rb><rt>あめ</rt></ruby> ① 与<ruby><rb>飴</rb><rt>あめ</rt></ruby> ⓪ 读音相同但重音不同，易混淆；此外在合成词中常读作「あま」，如：<ruby><rb>雨具</rb><rt>あまぐ</rt></ruby>、<ruby><rb>雨宿り</rb><rt>あまやどり</rt></ruby>。<ruby><rb>梅雨</rb><rt>つゆ</rt></ruby>（雨季）也可在学术语境读作「<ruby><rb>梅雨</rb><rt>ばいう</rt></ruby>」。
易错搭配：
1. × <ruby><rb>雨</rb><rt>あめ</rt></ruby>を<ruby><rb>降</rb><rt>ふ</rt></ruby>る → ○ <ruby><rb>雨</rb><rt>あめ</rt></ruby>が<ruby><rb>降</rb><rt>ふ</rt></ruby>る（表示“下雨”应以雨作主语，用「が」）
2. × <ruby><rb>雨</rb><rt>あめ</rt></ruby>を<ruby><rb>止</rb><rt>や</rt></ruby>める → ○ <ruby><rb>雨</rb><rt>あめ</rt></ruby>が<ruby><rb>止</rb><rt>や</rt></ruby>む（“雨停”用不及物动词「止む」）
3. 被雨淋到常说：<ruby><rb>雨</rb><rt>あめ</rt></ruby>に<ruby><rb>降</rb><rt>ふ</rt></ruby>られる（带有“很倒霉、被动挨淋”的语气），而非直译的他动被动表达
易错词义：
1. <ruby><rb>雨</rb><rt>あめ</rt></ruby>：雨、水汽降落现象；<ruby><rb>飴</rb><rt>あめ</rt></ruby>：糖果，二者含义完全不同
2. <ruby><rb>雨</rb><rt>あめ</rt></ruby> vs. <ruby><rb>雨天</rb><rt>うてん</rt></ruby>：前者是“雨（现象）”，后者多指“雨天（状态/条件）”，常用于安排通知（如「<ruby><rb>雨天</rb><rt>うてん</rt></ruby><ruby><rb>中止</rb><rt>ちゅうし</rt></ruby>」）<br><br>


近义词：
1. <ruby><rb>降雨</rb><rt>こうう</rt></ruby>
区别：<ruby><rb>雨</rb><rt>あめ</rt></ruby>是通用口语词；<ruby><rb>降雨</rb><rt>こうう</rt></ruby>偏书面、技术语，用于统计、观测或报道。
例句：
<ruby><rb>雨</rb><rt>あめ</rt></ruby>：<ruby><rb>昼</rb><rt>ひる</rt></ruby>から<ruby><rb>雨</rb><rt>あめ</rt></ruby>が<ruby><rb>降</rb><rt>ふ</rt></ruby>り<ruby><rb>出</rb><rt>だ</rt></ruby>した。
从中午开始下起雨来。
<ruby><rb>降雨</rb><rt>こうう</rt></ruby>：<ruby><rb>午後</rb><rt>ごご</rt></ruby>は<ruby><rb>各地</rb><rt>かくち</rt></ruby>で<ruby><rb>降雨</rb><rt>こうう</rt></ruby>が<ruby><rb>観測</rb><rt>かんそく</rt></ruby>された。
下午各地观测到了降雨。

2. <ruby><rb>雨天</rb><rt>うてん</rt></ruby>
区别：<ruby><rb>雨</rb><rt>あめ</rt></ruby>指自然现象；<ruby><rb>雨天</rb><rt>うてん</rt></ruby>指状态/条件，多用于活动安排与规则表述。
例句：
<ruby><rb>雨</rb><rt>あめ</rt></ruby>：<ruby><rb>雨</rb><rt>あめ</rt></ruby>の<ruby><rb>日</rb><rt>ひ</rt></ruby>は<ruby><rb>外出</rb><rt>がいしゅつ</rt></ruby>を<ruby><rb>控</rb><rt>ひか</rt></ruby>える。
下雨天尽量少外出。
<ruby><rb>雨天</rb><rt>うてん</rt></ruby>：<ruby><rb>試合</rb><rt>しあい</rt></ruby>は<ruby><rb>雨天</rb><rt>うてん</rt></ruby>のため<ruby><rb>中止</rb><rt>ちゅうし</rt></ruby>です。
比赛因雨天而中止。<br><br>


反义词：
1. <ruby><rb>晴</rb><rt>は</rt></ruby>れ
名词：晴天、放晴（与“雨”在天气语境中相对）
例句：
<ruby><rb>明日</rb><rt>あした</rt></ruby>は<ruby><rb>晴</rb><rt>は</rt></ruby>れだ。
明天是晴天。

2. <ruby><rb>曇</rb><rt>くも</rt></ruby>り
名词：多云、阴天（同属天气状态，常与“雨”并列对比）
例句：
<ruby><rb>今日</rb><rt>きょう</rt></ruby>は<ruby><rb>曇</rb><rt>くも</rt></ruby>りで、<ruby><rb>雨</rb><rt>あめ</rt></ruby>は<ruby><rb>降</rb><rt>ふ</rt></ruby>らないだろう。
今天多云，应该不会下雨。<br><br>


扩展：
1. 比喻义：“～の<ruby><rb>雨</rb><rt>あめ</rt></ruby>”表示“如雨般大量落下/到来”，如：<ruby><rb>拍手</rb><rt>はくしゅ</rt></ruby>の<ruby><rb>雨</rb><rt>あめ</rt></ruby>（如潮的掌声）、<ruby><rb>質問</rb><rt>しつもん</rt></ruby>の<ruby><rb>雨</rb><rt>あめ</rt></ruby>（接连不断的问题）。
2. 读音变化：作构词要素时常读「あま」，如：<ruby><rb>雨具</rb><rt>あまぐ</rt></ruby>（雨具）、<ruby><rb>雨傘</rb><rt>あまがさ</rt></ruby>（雨伞）、<ruby><rb>雨宿り</rb><rt>あまやどり</rt></ruby>（避雨）。
3. 天气表达：预报中常见「<ruby><rb>雨</rb><rt>あめ</rt></ruby>のち<ruby><rb>晴</rb><rt>は</rt></ruby>れ」（先雨后晴）、「ところにより<ruby><rb>雨</rb><rt>あめ</rt></ruby>」（局部地区有雨）。
''';

    const fewShotUserJa2 = '单词为："忘れ物（わすれもの）⓪"；单词词义为："遗失物"。请生成遵循上述要求，生成词解 HTML 内容。';
    const fewShotAssistantJa2 = r'''
单词含义：
名词：遗失物；遗留物；忘带/落在某处的东西
读音：わすれもの
声调：⓪
常用搭配：
1. <ruby><rb>忘</rb><rt>わす</rt></ruby>れ<ruby><rb>物</rb><rt>もの</rt></ruby>をする（把东西忘在某处）
2. <ruby><rb>忘</rb><rt>わす</rt></ruby>れ<ruby><rb>物</rb><rt>もの</rt></ruby>に<ruby><rb>気</rb><rt>き</rt></ruby>づく（发觉有遗忘物）
3. <ruby><rb>忘</rb><rt>わす</rt></ruby>れ<ruby><rb>物</rb><rt>もの</rt></ruby>を<ruby><rb>取</rb><rt>と</rt></ruby>りに<ruby><rb>戻</rb><rt>もど</rt></ruby>る（返回去取遗忘物）
4. <ruby><rb>忘</rb><rt>わす</rt></ruby>れ<ruby><rb>物</rb><rt>もの</rt></ruby>を<ruby><rb>届</rb><rt>とど</rt></ruby>ける（把捡到的遗忘物上交）
5. <ruby><rb>忘</rb><rt>わす</rt></ruby>れ<ruby><rb>物</rb><rt>もの</rt></ruby>の<ruby><rb>届</rb><rt>とど</rt></ruby>け<ruby><rb>出</rb><rt>で</rt></ruby>（遗失申报）
6. <ruby><rb>忘</rb><rt>わす</rt></ruby>れ<ruby><rb>物取扱所</rb><rt>ものとりあつかいじょ</rt></ruby>（遗失物受理处）
7. お<ruby><rb>忘</rb><rt>わす</rt></ruby>れ<ruby><rb>物</rb><rt>もの</rt></ruby>センター（遗失物中心）
8. <ruby><rb>忘</rb><rt>わす</rt></ruby>れ<ruby><rb>物</rb><rt>もの</rt></ruby><ruby><rb>防止</rb><rt>ぼうし</rt></ruby>タグ（防忘标签）
常用短语：
1. お<ruby><rb>忘</rb><rt>わす</rt></ruby>れ<ruby><rb>物</rb><rt>もの</rt></ruby>にご<ruby><rb>注</rb><rt>ちゅう</rt></ruby><ruby><rb>意</rb><rt>い</rt></ruby>ください（请注意不要遗忘物品）
2. お<ruby><rb>忘</rb><rt>わす</rt></ruby>れ<ruby><rb>物</rb><rt>もの</rt></ruby>はありませんか（您有没有遗忘物）
3. <ruby><rb>忘</rb><rt>わす</rt></ruby>れ<ruby><rb>物</rb><rt>もの</rt></ruby><ruby><rb>扱</rb><rt>あつか</rt></ruby>い（按遗失物处理）
4. <ruby><rb>忘</rb><rt>わす</rt></ruby>れ<ruby><rb>物</rb><rt>もの</rt></ruby><ruby><rb>受</rb><rt>う</rt></ruby>け<ruby><rb>取</rb><rt>と</rt></ruby>り（领取遗失物）
5. <ruby><rb>出</rb><rt>で</rt></ruby>かける<ruby><rb>前</rb><rt>まえ</rt></ruby>の<ruby><rb>忘</rb><rt>わす</rt></ruby>れ<ruby><rb>物</rb><rt>もの</rt></ruby>チェック（出门前防忘检查）


重点：
易错读音：读作「わすれもの」⓪（平板型）。公告与服务语境常用敬语形式「お<ruby><rb>忘</rb><rt>わす</rt></ruby>れ<ruby><rb>物</rb><rt>もの</rt></ruby>」；不要与「<ruby><rb>落</rb><rt>お</rt></ruby>とし<ruby><rb>物</rb><rt>もの</rt></ruby>」或「<ruby><rb>忘</rb><rt>わす</rt></ruby>れ<ruby><rb>事</rb><rt>ごと</rt></ruby>」读音与意义混淆。
易错搭配：
1. × <ruby><rb>忘</rb><rt>わす</rt></ruby>れ<ruby><rb>物</rb><rt>もの</rt></ruby>を<ruby><rb>落</rb><rt>お</rt></ruby>とす → ○ <ruby><rb>物</rb><rt>もの</rt></ruby>を<ruby><rb>落</rb><rt>お</rt></ruby>とす／<ruby><rb>落</rb><rt>お</rt></ruby>とし<ruby><rb>物</rb><rt>もの</rt></ruby>をする（“掉了东西”不用「忘れ物」）
2. × <ruby><rb>忘</rb><rt>わす</rt></ruby>れ<ruby><rb>物</rb><rt>もの</rt></ruby>を<ruby><rb>無</rb><rt>な</rt></ruby>くす（想表达“避免发生遗忘”）→ ○ <ruby><rb>忘</rb><rt>わす</rt></ruby>れ<ruby><rb>物</rb><rt>もの</rt></ruby>をしない／<ruby><rb>忘</rb><rt>わす</rt></ruby>れ<ruby><rb>物</rb><rt>もの</rt></ruby>を<ruby><rb>減</rb><rt>へ</rt></ruby>らす
3. 上交用法：○ <ruby><rb>忘</rb><rt>わす</rt></ruby>れ<ruby><rb>物</rb><rt>もの</rt></ruby>を<ruby><rb>駅</rb><rt>えき</rt></ruby>や<ruby><rb>交番</rb><rt>こうばん</rt></ruby>に<ruby><rb>届</rb><rt>とど</rt></ruby>ける（用「に＋届ける」表示上交地点）
易错词义：
1. 「<ruby><rb>忘</rb><rt>わす</rt></ruby>れ<ruby><rb>物</rb><rt>もの</rt></ruby>」：把东西忘在原处的遗留物；「<ruby><rb>落</rb><rt>お</rt></ruby>とし<ruby><rb>物</rb><rt>もの</rt></ruby>」：不知不觉掉落的东西
2. 「<ruby><rb>忘</rb><rt>わす</rt></ruby>れ<ruby><rb>事</rb><rt>ごと</rt></ruby>」指“忘记的事情/疏忽”，非具体物品
3. 「<ruby><rb>遺失物</rb><rt>いしつぶつ</rt></ruby>」偏法律/事务用语，多用于规章、警方/铁路管理语境


近义词：
1. <ruby><rb>落</rb><rt>お</rt></ruby>とし<ruby><rb>物</rb><rt>もの</rt></ruby>（不知不觉掉落的物品）
区别：「<ruby><rb>忘</rb><rt>わす</rt></ruby>れ<ruby><rb>物</rb><rt>もの</rt></ruby>」强调“遗留在原处”；「<ruby><rb>落</rb><rt>お</rt></ruby>とし<ruby><rb>物</rb><rt>もの</rt></ruby>」强调“在路上等处掉落”且多由他人拾得。
例句：
忘れ物：<ruby><rb>駅</rb><rt>えき</rt></ruby>に<ruby><rb>忘</rb><rt>わす</rt></ruby>れ<ruby><rb>物</rb><rt>もの</rt></ruby>を<ruby><rb>取</rb><rt>と</rt></ruby>りに<ruby><rb>戻</rb><rt>もど</rt></ruby>った。
我返回车站去取遗忘物。
落とし物：<ruby><rb>道</rb><rt>みち</rt></ruby>で<ruby><rb>落</rb><rt>お</rt></ruby>とし<ruby><rb>物</rb><rt>もの</rt></ruby>を<ruby><rb>見</rb><rt>み</rt></ruby>つけ、<ruby><rb>交番</rb><rt>こうばん</rt></ruby>に<ruby><rb>届</rb><rt>とど</rt></ruby>けた。
我在路上捡到他人遗失物并送到了派出所。

2. <ruby><rb>遺失物</rb><rt>いしつぶつ</rt></ruby>（法律/事务用的“遗失物”）
区别：「<ruby><rb>遺失物</rb><rt>いしつぶつ</rt></ruby>」偏书面、制度/管理语境；「<ruby><rb>忘</rb><rt>わす</rt></ruby>れ<ruby><rb>物</rb><rt>もの</rt></ruby>」口语常用。
例句：
忘れ物：<ruby><rb>図書館</rb><rt>としょかん</rt></ruby>で<ruby><rb>忘</rb><rt>わす</rt></ruby>れ<ruby><rb>物</rb><rt>もの</rt></ruby>の<ruby><rb>受</rb><rt>う</rt></ruby>け<ruby><rb>取</rb><rt>と</rt></ruby>りをした。
我在图书馆办理了遗失物的领取。
遺失物：<ruby><rb>駅</rb><rt>えき</rt></ruby>では<ruby><rb>遺失物</rb><rt>いしつぶつ</rt></ruby>として<ruby><rb>管</rb><rt>かん</rt></ruby><ruby><rb>理</rb><rt>り</rt></ruby>される。
在车站会按“遗失物”进行管理。

3. <ruby><rb>置</rb><rt>お</rt></ruby>き<ruby><rb>忘</rb><rt>わす</rt></ruby>れ（把东西放下后忘记带走；偏动作/原因）
区别：「<ruby><rb>置</rb><rt>お</rt></ruby>き<ruby><rb>忘</rb><rt>わす</rt></ruby>れ」多指“置下就忘”的行为或原因；结果上的“物”则称「<ruby><rb>忘</rb><rt>わす</rt></ruby>れ<ruby><rb>物</rb><rt>もの</rt></ruby>」。
例句：
忘れ物：<ruby><rb>教室</rb><rt>きょうしつ</rt></ruby>の<ruby><rb>忘</rb><rt>わす</rt></ruby>れ<ruby><rb>物</rb><rt>もの</rt></ruby>が<ruby><rb>多</rb><rt>おお</rt></ruby>い。
教室里的遗忘物很多。
置き忘れ：<ruby><rb>会議室</rb><rt>かいぎしつ</rt></ruby>での<ruby><rb>置</rb><rt>お</rt></ruby>き<ruby><rb>忘</rb><rt>わす</rt></ruby>れが<ruby><rb>相次</rb><rt>あいつ</rt></ruby>いだ。
会议室里接连发生把东西落下不带走的情况。


反义词：
1. <ruby><rb>持</rb><rt>も</rt></ruby>ち<ruby><rb>物</rb><rt>もの</rt></ruby>
随身携带的物品；与“遗忘在外的物品”概念相对。
例句：
<ruby><rb>外出</rb><rt>がいしゅつ</rt></ruby><ruby><rb>前</rb><rt>まえ</rt></ruby>に<ruby><rb>持</rb><rt>も</rt></ruby>ち<ruby><rb>物</rb><rt>もの</rt></ruby>を<ruby><rb>確</rb><rt>かく</rt></ruby><ruby><rb>認</rb><rt>にん</rt></ruby>する。
出门前确认随身物品。

2. <ruby><rb>手荷物</rb><rt>てにもつ</rt></ruby>
手提/随身行李；在出行场景与“忘在外面的物品”相对。
例句：
<ruby><rb>手荷物</rb><rt>てにもつ</rt></ruby>から<ruby><rb>目</rb><rt>め</rt></ruby>を<ruby><rb>離</rb><rt>はな</rt></ruby>さないでください。
请不要让目光离开您的手提行李。


扩展：
1. 敬语与公告用法：服务场景常用「お<ruby><rb>忘</rb><rt>わす</rt></ruby>れ<ruby><rb>物</rb><rt>もの</rt></ruby>」「お<ruby><rb>忘</rb><rt>わす</rt></ruby>れ<ruby><rb>物</rb><rt>もの</rt></ruby>にご<ruby><rb>注</rb><rt>ちゅう</rt></ruby><ruby><rb>意</rb><rt>い</rt></ruby>ください」等表达。
2. 书写与派生：可写作「わすれもの」（平假名）；相关动名词「<ruby><rb>置</rb><rt>お</rt></ruby>き<ruby><rb>忘</rb><rt>わす</rt></ruby>れ」表示“放下后忘带走”的行为。
3. 实务用语对照：铁路/警方等管理语境多用「<ruby><rb>遺失物</rb><rt>いしつぶつ</rt></ruby>」，公告中常并列为「お<ruby><rb>忘</rb><rt>わす</rt></ruby>れ<ruby><rb>物</rb><rt>もの</rt></ruby>・<ruby><rb>落</rb><rt>お</rt></ruby>とし<ruby><rb>物</rb><rt>もの</rt></ruby>」。
''';

    const fewShotUserJa3 = '单词为："スケジュール（schedule）②③"；单词词义为："日程，安排"。请生成遵循上述要求，生成词解 HTML 内容。';
    const fewShotAssistantJa3 = r'''
单词含义：
名词：日程；安排；行程计划
读音：スケジュール
声调：②③
常用搭配：
1. スケジュールを<ruby><rb>立</rb><rt>た</rt></ruby>てる（制定日程）
2. スケジュールを<ruby><rb>組</rb><rt>く</rt></ruby>む（编排日程）
3. スケジュールを<ruby><rb>調整</rb><rt>ちょうせい</rt></ruby>する（调整日程）
4. スケジュールを<ruby><rb>管理</rb><rt>かんり</rt></ruby>する（管理日程）
5. スケジュールが<ruby><rb>詰</rb><rt>つ</rt></ruby>まっている（行程很满）
6. スケジュールが<ruby><rb>空</rb><rt>あ</rt></ruby>いている（有空档）
7. スケジュール<ruby><rb>通</rb><rt>どお</rt></ruby>りに<ruby><rb>進</rb><rt>すす</rt></ruby>める（按计划推进）
8. スケジュールを<ruby><rb>確認</rb><rt>かくにん</rt></ruby>する（确认日程）
常用短语：
1. スケジュール<ruby><rb>表</rb><rt>ひょう</rt></ruby>（日程表）
2. <ruby><rb>週間</rb><rt>しゅうかん</rt></ruby>スケジュール（周计划）
3. <ruby><rb>今週</rb><rt>こんしゅう</rt></ruby>のスケジュール（本周安排）
4. <ruby><rb>一日</rb><rt>いちにち</rt></ruby>のスケジュール（一天的安排）
5. スケジュール<ruby><rb>変更</rb><rt>へんこう</rt></ruby>（变更日程）
6. スケジュール<ruby><rb>管理</rb><rt>かんり</rt></ruby>（日程管理）
7. <ruby><rb>過密</rb><rt>かみつ</rt></ruby>スケジュール（过于紧凑的日程）
8. <ruby><rb>柔軟</rb><rt>じゅうなん</rt></ruby>なスケジュール（灵活的日程）


重点：
易错读音：重音在不同地区存在差异，两个发音“②”和“③”都可以使用。长音「ー」要准确发音，「ジュール」部分不应缩短。
アクセントは地域差があり「②」「③」どちらも用いられる。長音「ー」を<ruby><rb>正確</rb><rt>せいかく</rt></ruby>に発音（スケジュール／スケジュール）し、「ジュール」の部分を短くしないこと。表記では「スケジュール<ruby><rb>通</rb><rt>どお</rt></ruby>り」が推奨される（「スケジュール<ruby><rb>通</rb><rt>とお</rt></ruby>り」も見られる）。
易错搭配：
1. × スケジュールを<ruby><rb>立</rb><rt>た</rt></ruby>つ → ○ スケジュールを<ruby><rb>立</rb><rt>た</rt></ruby>てる（动词应为「立てる」）
2. × スケジュールが<ruby><rb>詰</rb><rt>つ</rt></ruby>んでいる → ○ スケジュールが<ruby><rb>詰</rb><rt>つ</rt></ruby>まっている（表达“很满”用「詰まる」）
3. × スケジュール<ruby><rb>通</rb><rt>とお</rt></ruby>りで<ruby><rb>進</rb><rt>すす</rt></ruby>める → ○ スケジュール<ruby><rb>通</rb><rt>どお</rt></ruby>りに<ruby><rb>進</rb><rt>すす</rt></ruby>める（副词用法「〜どおりに」）
易错词义：
1. スケジュール vs. <ruby><rb>予定</rb><rt>よてい</rt></ruby>：前者偏指“时程安排（时间轴上的分配）”，后者泛指“打算/计划（意向或事项）”。
2. スケジュール vs. <ruby><rb>日程</rb><rt>にってい</rt></ruby>：「日程」多用于正式场合、会议或<ruby><rb>行事</rb><rt>ぎょうじ</rt></ruby>的逐日安排；「スケジュール」更口语、范围更广。


近义词：
1. <ruby><rb>予定</rb><rt>よてい</rt></ruby>（预定、打算）
区别：「スケジュール」强调时间表式的安排；「<ruby><rb>予定</rb><rt>よてい</rt></ruby>」强调意向或将要做的事项本身。
例句：
スケジュール：<ruby><rb>来週</rb><rt>らいしゅう</rt></ruby>のスケジュールを<ruby><rb>調整</rb><rt>ちょうせい</rt></ruby>する。
调整下周的日程。
<ruby><rb>予定</rb><rt>よてい</rt></ruby>：<ruby><rb>来週</rb><rt>らいしゅう</rt></ruby>の<ruby><rb>予定</rb><rt>よてい</rt></ruby>を<ruby><rb>変更</rb><rt>へんこう</rt></ruby>した。
把下周的计划改了。

2. <ruby><rb>日程</rb><rt>にってい</rt></ruby>（逐日安排、日程）
区别：「<ruby><rb>日程</rb><rt>にってい</rt></ruby>」多见于正式通知、会议/活动安排；「スケジュール」常用于个人或业务上的整体时间表。
例句：
スケジュール：<ruby><rb>会議</rb><rt>かいぎ</rt></ruby>のスケジュールを<ruby><rb>組</rb><rt>く</rt></ruby>む。
制定会议的时间表。
<ruby><rb>日程</rb><rt>にってい</rt></ruby>：<ruby><rb>会議</rb><rt>かいぎ</rt></ruby>の<ruby><rb>日程</rb><rt>にってい</rt></ruby>を<ruby><rb>発表</rb><rt>はっぴょう</rt></ruby>する。
公布会议日程。

3. タイムテーブル（时刻表、时间安排表）
区别：「タイムテーブル」多指列车/航空等时刻表或活动节目单式的时序清单；「スケジュール」更泛用。
例句：
スケジュール：<ruby><rb>発表会</rb><rt>はっぴょうかい</rt></ruby>のスケジュールを<ruby><rb>確認</rb><rt>かくにん</rt></ruby>する。
确认发布会的日程。
タイムテーブル：<ruby><rb>電車</rb><rt>でんしゃ</rt></ruby>のタイムテーブルを<ruby><rb>確認</rb><rt>かくにん</rt></ruby>する。
确认电车的时刻表。

4. <ruby><rb>計画</rb><rt>けいかく</rt></ruby>（计划、规划）
区别：「<ruby><rb>計画</rb><rt>けいかく</rt></ruby>」强调内容设计与方案本身；「スケジュール」强调时间安排与进度。
例句：
スケジュール：<ruby><rb>発売</rb><rt>はつばい</rt></ruby>のスケジュールを<ruby><rb>決</rb><rt>き</rt></ruby>める。
敲定上市的时间安排。
<ruby><rb>計画</rb><rt>けいかく</rt></ruby>：<ruby><rb>新製品</rb><rt>しんせいひん</rt></ruby>の<ruby><rb>計画</rb><rt>けいかく</rt></ruby>を<ruby><rb>立</rb><rt>た</rt></ruby>てる。
制定新产品的计划。


反义词：
1. <ruby><rb>未定</rb><rt>みてい</rt></ruby>
尚未确定、没有敲定的状态。
例句：
スケジュールは<ruby><rb>未定</rb><rt>みてい</rt></ruby>です。
日程尚未确定。
2. <ruby><rb>無計画</rb><rt>むけいかく</rt></ruby>
无计划、缺乏安排；在工作/<ruby><rb>行動</rb><rt>こうどう</rt></ruby>语境下与“有日程安排”相对。
例句：
スケジュールを<ruby><rb>立</rb><rt>た</rt></ruby>てずに<ruby><rb>出張</rb><rt>しゅっちょう</rt></ruby>するのは<ruby><rb>無計画</rb><rt>むけいかく</rt></ruby>だ。
不做日程安排就出差是很没有计划的。


扩展：
1. 状态表达：<ruby><rb>過密</rb><rt>かみつ</rt></ruby>（很满）、<ruby><rb>余裕</rb><rt>よゆう</rt></ruby>がある（宽松）、<ruby><rb>前倒</rb><rt>まえだお</rt></ruby>し／<ruby><rb>後</rb><rt>あと</rt></ruby>ろ<ruby><rb>倒</rb><rt>だお</rt></ruby>し（把进度前移/后延）。
2. IT用法：スケジューリング／スケジューラー（<ruby><rb>定期</rb><rt>ていき</rt></ruby><ruby><rb>実行</rb><rt>じっこう</rt></ruby>や<ruby><rb>予約</rb><rt>よやく</rt></ruby>を<ruby><rb>管理</rb><rt>かんり</rt></ruby>する<ruby><rb>機能</rb><rt>きのう</rt></ruby>）。
3. 表记习惯：「スケジュール<ruby><rb>通</rb><rt>どお</rt></ruby>り」（按原定计划）、「スケジュール<ruby><rb>感</rb><rt>かん</rt></ruby>」（对工期/所需时间的<ruby><rb>感覚</rb><rt>かんかく</rt></ruby>，商务口语）。
''';

    final body = jsonEncode({
      'model': model,
      'messages': [
        {'role': 'system', 'content': system},
        // {'role': 'user', 'content': fewShotUserEn},
        // {'role': 'assistant', 'content': fewShotAssistantEn},
        {'role': 'user', 'content': fewShotUserJa},
        {'role': 'assistant', 'content': fewShotAssistantJa},
        {'role': 'user', 'content': fewShotUserJa2},
        {'role': 'assistant', 'content': fewShotAssistantJa2},
        {'role': 'user', 'content': fewShotUserJa3},
        {'role': 'assistant', 'content': fewShotAssistantJa3},
        {'role': 'user', 'content': user},
      ],
      'temperature': temperature,
      "top_p": 1,
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