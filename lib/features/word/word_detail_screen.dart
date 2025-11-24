import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_word_dictation/features/dictionary/screens/dictionary_query_screen.dart';
import 'package:flutter_word_dictation/shared/models/word.dart';
import 'package:flutter_word_dictation/core/services/example_sentence_service.dart';
import 'package:flutter_word_dictation/shared/models/example_sentence.dart';
import 'package:flutter_word_dictation/core/services/word_explanation_service.dart';
import 'package:flutter_word_dictation/shared/models/word_explanation.dart';
import 'package:flutter_word_dictation/core/models/dictionary.dart';
import 'package:flutter_word_dictation/core/services/dictionary_service.dart';
import 'package:flutter_word_dictation/core/services/dictionary_query_service.dart';
import 'package:flutter_word_dictation/core/services/ai_example_service.dart';
 
import 'package:flutter_word_dictation/core/services/ai_word_explanation_service.dart';
import 'package:flutter_word_dictation/core/services/config_service.dart';
import 'package:flutter_word_dictation/shared/widgets/word_explanation_renderer.dart';

 

class WordDetailScreen extends StatefulWidget {
  final Word word;
  final List<Word>? wordList;
  final int? initialIndex;

  const WordDetailScreen({
    super.key,
    required this.word,
    this.wordList,
    this.initialIndex,
  });

  @override
  State<WordDetailScreen> createState() => _WordDetailScreenState();
}

class _WordDetailScreenState extends State<WordDetailScreen> {
  final ExampleSentenceService _exampleService = ExampleSentenceService();
  List<ExampleSentence> _examples = [];
  bool _loading = true;
  final WordExplanationService _explanationService = WordExplanationService();
  WordExplanation? _explanation;
  bool _expLoading = true;
  late ValueNotifier<int> _currentIndexNotifier;
  PageController? _pageController;
  final DictionaryService _dictionaryService = DictionaryService();
  final DictionaryQueryService _dictionaryQueryService = DictionaryQueryService();
  List<Dictionary> _dictionaries = [];

  

  

  Word get _currentWord {
    if (widget.wordList != null && _currentIndexNotifier.value >= 0 && _currentIndexNotifier.value < widget.wordList!.length) {
      return widget.wordList![_currentIndexNotifier.value];
    }
    return widget.word;
  }

  @override
  void initState() {
    super.initState();
    final initialIndex = widget.wordList != null
        ? (widget.initialIndex != null && widget.initialIndex! >= 0 && widget.initialIndex! < widget.wordList!.length
            ? widget.initialIndex!
            : (widget.wordList!.indexWhere((element) => element.id == widget.word.id) >= 0
                ? widget.wordList!.indexWhere((element) => element.id == widget.word.id)
                : 0))
        : 0;
    _currentIndexNotifier = ValueNotifier<int>(initialIndex);
    final word = _currentWord;
    _loadExamples(word: word);
    _loadExplanation(word: word);
    _loadDictionaries();
    _currentIndexNotifier.addListener(_onWordIndexChanged);
  }

  @override
  void dispose() {
    _currentIndexNotifier.removeListener(_onWordIndexChanged);
    _currentIndexNotifier.dispose();
    _pageController?.dispose();
    _dictionaryQueryService.dispose();
    super.dispose();
  }

  void _onWordIndexChanged() {
    final word = _currentWord;
    _loadExamples(word: word);
    _loadExplanation(word: word);
  }

  Future<void> _loadDictionaries() async {
    final ds = await _dictionaryService.getDictionaries();
    if (mounted) {
      setState(() {
        _dictionaries = ds;
      });
    }
  }

  Future<void> _loadExamples({required Word word}) async {
    if (word.id != null) {
      final data = await _exampleService.getExamplesByWordId(word.id!);
      if (mounted) {
        setState(() {
          _examples = data;
          _loading = false;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _examples = [];
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadExplanation({required Word word}) async {
    if (word.id != null) {
      final data = await _explanationService.getByWordId(word.id!);
      if (mounted) {
        setState(() {
          _explanation = data;
          _expLoading = false;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _explanation = null;
          _expLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: ValueListenableBuilder<int>(
          valueListenable: _currentIndexNotifier,
          builder: (_, __, ___) => Text(_currentWord.prompt),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _pageController ??= PageController(initialPage: _currentIndexNotifier.value),
              itemCount: widget.wordList?.length ?? 1,
              physics: widget.wordList != null && widget.wordList!.length > 1
                  ? const PageScrollPhysics()
                  : const NeverScrollableScrollPhysics(),
              onPageChanged: (index) {
                if (widget.wordList != null && index >= 0 && index < widget.wordList!.length) {
                  setState(() {
                    _loading = true;
                    _examples = [];
                    _expLoading = true;
                    _explanation = null;
                  });
                  _currentIndexNotifier.value = index;
                }
              },
              itemBuilder: (context, pageIndex) {
                final currentWord = widget.wordList != null ? widget.wordList![pageIndex] : _currentWord;
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  child: ValueListenableBuilder<int>(
                    valueListenable: _currentIndexNotifier,
                    builder: (_, currentIndex, __) {
                      if (widget.wordList != null && currentIndex != pageIndex) {
                        return const SizedBox.shrink();
                      }
                      return _buildWordContent(context, currentWord);
                    },
                  ),
                );
              },
            ),
          ),
          _buildBottomNavigationBar(context),
        ],
      ),
    );
  }

  void _goPrev() {
    final controller = _pageController;
    if (controller != null && controller.hasClients) {
      controller.previousPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  }

  void _goNext() {
    final controller = _pageController;
    if (controller != null && controller.hasClients) {
      controller.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  }

  Widget _buildBottomNavigationBar(BuildContext context) {
    final total = widget.wordList?.length ?? 1;
    if (widget.wordList == null || total <= 1) {
      return const SizedBox.shrink();
    }
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          boxShadow: const [
            BoxShadow(
              blurRadius: 6,
              offset: Offset(0, -2),
              color: Color(0x14000000),
            ),
          ],
        ),
        child: ValueListenableBuilder<int>(
          valueListenable: _currentIndexNotifier,
          builder: (_, index, __) {
            final prevEnabled = total > 1 && index > 0;
            final nextEnabled = total > 1 && index < total - 1;
            return Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: prevEnabled ? _goPrev : null,
                    icon: const Icon(Icons.chevron_left),
                    label: const Text('上一个'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: nextEnabled ? _goNext : null,
                    icon: const Icon(Icons.chevron_right),
                    label: const Text('下一个'),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildWordContent(BuildContext context, Word word) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    word.prompt,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    word.answer,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (word.partOfSpeech != null)
                        Chip(
                          label: Text(word.partOfSpeech!),
                          backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
                        ),
                      if (word.level != null)
                        Chip(
                          label: Text(word.level!),
                          backgroundColor: Theme.of(context).colorScheme.tertiaryContainer,
                        ),
                      if (word.category != null)
                        Chip(
                          label: Text(word.category!),
                          backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: () {
                          if (word.id == null) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先保存单词')));
                            return;
                          }
                          _generateExplanation(word);
                        },
                        icon: const Icon(Icons.psychology),
                        label: const Text('AI生成词解'),
                      ),
                      const SizedBox(width: 8),
                      
                      const Spacer(),
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => DictionaryQueryScreen(initialQuery: word.prompt),
                            ),
                          );
                        },
                        icon: const Icon(Icons.search),
                        label: const Text('词典查询'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_expLoading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            ),
          )
        else if (_explanation == null)
          SizedBox(
            width: double.infinity,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.article, size: 18, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '暂无词解',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                          ),
                          
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          SizedBox(
            width: double.infinity,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Word explanation (now includes examples from JSON)
                    _buildExplanationHtml(context: context, html: _explanation!.html),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildExplanationHtml({required BuildContext context, required String html}) {
    // html field now contains JSON data
    return WordExplanationRenderer(
      jsonData: html,
      sourceLanguage: null, // Language will be inferred from JSON content
    );
  }

  Widget _buildRubyText({required BuildContext context, required String html, required String plain}) {
    final baseStyle = Theme.of(context).textTheme.bodyLarge?.copyWith(
      fontWeight: FontWeight.w600,
    );
    final rubyStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      fontSize: (Theme.of(context).textTheme.bodySmall?.fontSize ?? 12) * 0.9,
    );

    if (html.isEmpty) {
      return Text(plain, style: baseStyle);
    }

    final spans = _rubySpansFromHtml(html, baseStyle, rubyStyle);
    return RichText(
      text: TextSpan(
        children: spans,
        style: baseStyle,
      ),
    );
  }

  

  List<InlineSpan> _rubySpansFromHtml(String html, TextStyle? baseStyle, TextStyle? rubyStyle) {
    final List<InlineSpan> spans = [];
    final rubyReg = RegExp(r"<ruby>([\s\S]*?)<\/ruby>", multiLine: true);
    int lastIndex = 0;

    for (final match in rubyReg.allMatches(html)) {
      // Add preceding non-ruby text (strip any stray tags)
      if (match.start > lastIndex) {
        final before = html.substring(lastIndex, match.start).replaceAll(RegExp(r"<[^>]+>"), "");
        if (before.isNotEmpty) {
          spans.add(TextSpan(text: before, style: baseStyle));
        }
      }

      final rubyBlock = (match.group(1) ?? '').replaceAll(RegExp(r"<rp>[\s\S]*?</rp>"), '');

      final rbs = RegExp(r"<rb>([\s\S]*?)<\/rb>").allMatches(rubyBlock).map((m) => m.group(1) ?? '').toList();
      final rts = RegExp(r"<rt>([\s\S]*?)<\/rt>").allMatches(rubyBlock).map((m) => m.group(1) ?? '').toList();

      if (rbs.isEmpty && rts.isEmpty) {
        // fallback: no explicit rb/rt, treat ruby block as plain
        final plainBlock = rubyBlock.replaceAll(RegExp(r"<[^>]+>"), "");
        if (plainBlock.isNotEmpty) {
          spans.add(TextSpan(text: plainBlock, style: baseStyle));
        }
      } else {
        final count = (rbs.length > rts.length) ? rbs.length : rts.length;
        for (int i = 0; i < count; i++) {
          final rb = i < rbs.length ? rbs[i] : '';
          final rt = i < rts.length ? rts[i] : '';
          spans.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.bottom,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (rt.isNotEmpty)
                      Text(rt, style: rubyStyle, textAlign: TextAlign.center),
                    if (rb.isNotEmpty)
                      Text(rb, style: baseStyle, textAlign: TextAlign.left),
                  ],
                ),
              ),
            ),
          );
        }
      }

      lastIndex = match.end;
    }

    // Add remaining text after last ruby block
    if (lastIndex < html.length) {
      final after = html.substring(lastIndex).replaceAll(RegExp(r"<[^>]+>"), "");
      if (after.isNotEmpty) {
        spans.add(TextSpan(text: after, style: baseStyle));
      }
    }

    return spans;
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

  Future<(List<String>, List<Map<String, String>>)> _autoCollectSources(Word word) async {
    if (_dictionaries.isEmpty) {
      await _loadDictionaries();
    }
    final ai = await AIWordExplanationService.getInstance();
    final norm = await ai.normalizeWord(prompt: word.prompt);
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
    for (final d in _dictionaries) {
      final List<Map<String, String>> list = [];
      for (final t in terms) {
        final keys = await _dictionaryQueryService.searchKeys(d, t, limit: 32);
        for (final k in keys) {
          final html0 = await _dictionaryQueryService.lookupWord(d, k);
          final h = (html0 ?? '').trim();
          if (h.isNotEmpty && _htmlMatchesTerms(h, terms)) {
            final trunc = h.length > 2000 ? h.substring(0, 2000) : h;
            list.add({'key': k, 'html': trunc});
          }
        }
      }
      if (list.isEmpty) {
        for (final t in terms) {
          final keys = await _dictionaryQueryService.searchKeys(d, t, limit: 8);
          for (final k in keys) {
            final html0 = await _dictionaryQueryService.lookupWord(d, k);
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

    final picks = await ai.pickBestDictionaryEntries(prompt: word.prompt, answer: word.answer, entries: entries);
    final htmls = <String>[];
    final metas = <Map<String, String>>[];
    for (final dp in picks.keys) {
      final chosen = (picks[dp] ?? '') as String;
      if (chosen.trim().isEmpty) continue;
      Dictionary? dict;
      for (final d in _dictionaries) {
        if (d.path == dp) {
          dict = d;
          break;
        }
      }
      if (dict == null) continue;
      final h = await _dictionaryQueryService.lookupWord(dict, chosen);
      final hh = (h ?? '').trim();
      if (hh.isNotEmpty) {
        htmls.add(hh);
        metas.add({'dictionary': dict.name, 'key': chosen});
      }
    }
    return (htmls, metas);
  }

  Future<void> _generateExplanation(Word word) async {
    if (word.id == null) return;
    String sourceDropdown = 'auto';
    String targetDropdown = 'auto';
    final TextEditingController sourceCustomController = TextEditingController();
    final TextEditingController targetCustomController = TextEditingController();
    final ok = await showDialog<bool>(
          context: context,
          builder: (context) {
            return StatefulBuilder(
              builder: (context, setState) => AlertDialog(
                title: const Text('选择语言（词解生成）'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: sourceDropdown,
                            items: const [
                              DropdownMenuItem(value: 'auto', child: Text('原文自动识别')),
                              DropdownMenuItem(value: 'ja', child: Text('日语 ja')),
                              DropdownMenuItem(value: 'zh', child: Text('中文 zh')),
                              DropdownMenuItem(value: 'en', child: Text('英语 en')),
                              DropdownMenuItem(value: 'de', child: Text('德语 de')),
                              DropdownMenuItem(value: 'fr', child: Text('法语 fr')),
                              DropdownMenuItem(value: 'ko', child: Text('韩语 ko')),
                              DropdownMenuItem(value: 'custom', child: Text('自定义')),
                            ],
                            onChanged: (v) => setState(() => sourceDropdown = v ?? 'auto'),
                            decoration: const InputDecoration(labelText: '原文语言（常用）'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: targetDropdown,
                            items: const [
                              DropdownMenuItem(value: 'auto', child: Text('译文自动识别')),
                              DropdownMenuItem(value: 'zh', child: Text('中文 zh')),
                              DropdownMenuItem(value: 'ja', child: Text('日语 ja')),
                              DropdownMenuItem(value: 'en', child: Text('英语 en')),
                              DropdownMenuItem(value: 'de', child: Text('德语 de')),
                              DropdownMenuItem(value: 'fr', child: Text('法语 fr')),
                              DropdownMenuItem(value: 'ko', child: Text('韩语 ko')),
                              DropdownMenuItem(value: 'custom', child: Text('自定义')),
                            ],
                            onChanged: (v) => setState(() => targetDropdown = v ?? 'auto'),
                            decoration: const InputDecoration(labelText: '译文语言（常用）'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (sourceDropdown == 'custom')
                      TextField(
                        controller: sourceCustomController,
                        decoration: const InputDecoration(
                          labelText: '原文语言（自定义代码，可选）',
                          hintText: '如 ja, zh-CN, en-US，留空则自动或常用选择',
                        ),
                      ),
                    if (targetDropdown == 'custom')
                      TextField(
                        controller: targetCustomController,
                        decoration: const InputDecoration(
                          labelText: '译文语言（自定义代码，可选）',
                          hintText: '如 zh, en-GB，留空则自动或常用选择',
                        ),
                      ),
                  ],
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('取消')),
                  TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('开始')),
                ],
              ),
            );
          },
        ) ?? false;
    if (!ok) return;
    final srcLang = sourceDropdown == 'custom'
        ? (sourceCustomController.text.trim().isEmpty ? null : sourceCustomController.text.trim())
        : (sourceDropdown == 'auto' ? null : sourceDropdown);
    final tgtLang = targetDropdown == 'custom'
        ? (targetCustomController.text.trim().isEmpty ? null : targetCustomController.text.trim())
        : (targetDropdown == 'auto' ? null : targetDropdown);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        title: Text('正在生成词解'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator(),
            SizedBox(height: 8),
            Text('请稍候…'),
          ],
        ),
      ),
    );
    try {
      final ai = await AIWordExplanationService.getInstance();
      final cfg = await ConfigService.getInstance();
      final useSources = await cfg.getUseDictionarySources();
      final sources = useSources ? await ai.collectSourcesForWord(word) : (<String>[], const <Map<String, String>>[]);
      var jsonData = await ai.generateExplanationHtmlStructured(
        prompt: word.prompt,
        answer: word.answer,
        sourceLanguage: srcLang,
        targetLanguage: tgtLang,
        sourcesHtml: sources.$1,
        sourcesMeta: sources.$2,
      );
      
      // Embed sources in JSON if available
      if (sources.$2.isNotEmpty) {
        try {
          final data = jsonDecode(jsonData) as Map<String, dynamic>;
          data['sources'] = sources.$2.map((m) => {
            'dictionary': m['dictionary'] ?? '',
            'key': m['key'] ?? '',
          }).toList();
          jsonData = jsonEncode(data);
        } catch (_) {
          // If JSON parsing fails, keep original
        }
      }

      final now = DateTime.now();
      final exp = WordExplanation(
        id: null,
        wordId: word.id!,
        html: jsonData,
        sourceModel: null,
        createdAt: now,
        updatedAt: now,
      );
      await _explanationService.upsertForWord(exp);
      final latest = await _explanationService.getByWordId(word.id!);

      if (mounted) {
        Navigator.of(context).pop();
        setState(() {
          _explanation = latest;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已为 "${word.prompt}" 生成词解')),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('生成失败：$e')),
      );
    }
  }

  
}
// 移至文件顶部统一导入（见上），删除中部重复导入
