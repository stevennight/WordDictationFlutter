import 'package:flutter/material.dart';
import 'package:flutter_word_dictation/core/models/dictionary.dart';
import 'package:flutter_word_dictation/core/services/dictionary_query_service.dart';
import 'package:flutter_word_dictation/core/services/dictionary_service.dart';
import 'package:flutter_word_dictation/shared/models/word.dart';
import 'package:flutter_word_dictation/core/services/example_sentence_service.dart';
import 'package:flutter_word_dictation/shared/models/example_sentence.dart';
import 'package:flutter_word_dictation/core/services/ai_example_service.dart';
import 'package:flutter_word_dictation/shared/widgets/ai_generate_examples_dialog.dart';
import 'package:flutter_word_dictation/shared/widgets/ai_generate_examples_strategy_dialog.dart';
import 'package:flutter_word_dictation/core/services/word_explanation_service.dart';
import 'package:flutter_word_dictation/core/services/ai_word_explanation_service.dart';
import 'package:flutter_word_dictation/shared/models/word_explanation.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:audioplayers/audioplayers.dart';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'dart:io';

class _DictKeyItem {
  final Dictionary dictionary;
  final String key;
  const _DictKeyItem(this.dictionary, this.key);
}

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
  int _selectedDictionaryIndex = -1;
  final TextEditingController _dictionarySearchController = TextEditingController();
  String? _dictionarySearchResult;
  bool _isDictionaryLoading = false;
  List<_DictKeyItem> _dictionarySearchEntries = [];
  Dictionary? _dictionarySearchSource;
  final AudioPlayer _audioPlayer = AudioPlayer();

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
    _dictionarySearchController.dispose();
    _dictionaryQueryService.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  void _onWordIndexChanged() {
    final word = _currentWord;
    _loadExamples(word: word);
    _loadExplanation(word: word);
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
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _generateExplanation(word),
                        icon: const Icon(Icons.psychology),
                        label: const Text('AI生成词解'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: () => _showAIGenerateExamplesDialog(word),
                        icon: const Icon(Icons.auto_awesome),
                        label: const Text('AI生成例句'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: _listMddRoot,
                        icon: const Icon(Icons.folder_open),
                        label: const Text('列出MDD根目录'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        _buildDictionaryLookup(context),
        const SizedBox(height: 16),
        Text(
          '词解',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
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
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: OutlinedButton.icon(
                              onPressed: () => _generateExplanation(word),
                              icon: const Icon(Icons.psychology),
                              label: const Text('使用AI生成词解'),
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
                child: _buildExplanationHtml(context: context, html: _explanation!.html),
              ),
            ),
          ),
        Text(
          '例句',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (_loading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            ),
          )
        else if (_examples.isEmpty)
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              '暂无例句',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _examples.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final ex = _examples[index];
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.format_quote, size: 16, color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 6),
                          Text(
                            ex.senseText.isNotEmpty ? ex.senseText : '（未标注词义）',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _buildRubyText(
                        context: context,
                        html: ex.textHtml,
                        plain: ex.textPlain,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        ex.textTranslation,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                      if (ex.grammarNote.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          ex.grammarNote,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildExplanationHtml({required BuildContext context, required String html}) {
    final normalized = html.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
    final plain = normalized.replaceAll(RegExp(r'<[^>]+>'), '');
    return _buildRubyText(context: context, html: normalized, plain: plain);
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

  Future<void> _playSound(String url) async {
    final dict = _dictionarySearchSource ?? (_selectedDictionaryIndex == -1
        ? (_dictionaries.isNotEmpty ? _dictionaries.first : null)
        : _dictionaries[_selectedDictionaryIndex]);
    if (dict == null) return;
    try {
      final bytes = await _dictionaryQueryService.readMedia(dict, url);
      if (bytes == null) return;
      final dir = await getTemporaryDirectory();
      final name = url.split('://').last;
      final matched = _dictionaryQueryService.lastResolvedMediaKey;
      final adjustedName = () {
        if (matched != null && matched.isNotEmpty) {
          final normalized = matched.replaceAll('\\', '/');
          final lastSeg = normalized.split('/').last;
          if (lastSeg.contains('.')) {
            return lastSeg;
          }
        }
        return name;
      }();
      final filePath = p.join(dir.path, adjustedName);
      final f = File(filePath);
      await f.writeAsBytes(bytes, flush: true);
      print('[WordDetail] media ready: ${bytes.length} bytes -> $filePath');
      await _audioPlayer.stop();
      await _audioPlayer.play(DeviceFileSource(filePath));
    } catch (_) {}
  }

  Future<void> _listMddRoot() async {
    final dict = _dictionarySearchSource ?? (_selectedDictionaryIndex == -1
        ? (_dictionaries.isNotEmpty ? _dictionaries.first : null)
        : _dictionaries[_selectedDictionaryIndex]);
    if (dict == null) return;
    try {
      final data = await _dictionaryQueryService.listMddRootAndDirs(dict, limit: 200);
      final items = data['root'] ?? const <String>[];
      final dirs = data['dirs'] ?? const <String>[];
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('MDD根层清单与目录摘要'),
            content: SizedBox(
              width: 520,
              height: 400,
              child: (items.isEmpty && dirs.isEmpty)
                  ? const Center(child: Text('无根目录内容或未找到MDD'))
                  : Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('目录摘要', style: Theme.of(context).textTheme.titleSmall),
                              const SizedBox(height: 6),
                              Expanded(
                                child: ListView.builder(
                                  itemCount: dirs.length,
                                  itemBuilder: (_, i) => ListTile(
                                    dense: true,
                                    leading: const Icon(Icons.folder),
                                    title: Text(dirs[i]),
                                    trailing: const Icon(Icons.chevron_right),
                                    onTap: () async {
                                      final raw = dirs[i];
                                      final name = () {
                                        final s = raw.trim();
                                        final idx = s.indexOf('(');
                                        final t = idx > 0 ? s.substring(0, idx).trim() : s;
                                        return t.startsWith('/') ? t.substring(1).trim() : t;
                                      }();
                                      final children = await _dictionaryQueryService.listMddDirChildren(dict, name, limit: 300);
                                      if (!context.mounted) return;
                                      await showDialog(
                                        context: context,
                                        builder: (context) {
                                          return AlertDialog(
                                            title: Text('目录 "$name" 子项样本'),
                                            content: SizedBox(
                                              width: 520,
                                              height: 400,
                                              child: children.isEmpty
                                                  ? const Center(child: Text('无子项或未找到'))
                                                  : ListView.builder(
                                                      itemCount: children.length,
                                                      itemBuilder: (_, j) => ListTile(
                                                        dense: true,
                                                        leading: const Icon(Icons.music_note),
                                                        title: Text(children[j]),
                                                      ),
                                                    ),
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () => Navigator.of(context).pop(),
                                                child: const Text('关闭'),
                                              ),
                                            ],
                                          );
                                        },
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('根层清单', style: Theme.of(context).textTheme.titleSmall),
                              const SizedBox(height: 6),
                              Expanded(
                                child: ListView.builder(
                                  itemCount: items.length,
                                  itemBuilder: (_, i) => ListTile(
                                    dense: true,
                                    leading: const Icon(Icons.music_note),
                                    title: Text(items[i]),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('关闭'),
              ),
            ],
          );
        },
      );
    } catch (_) {}
  }

  Future<Uint8List?> _loadMedia(String url) async {
    final dict = _dictionarySearchSource ?? (_selectedDictionaryIndex == -1
        ? (_dictionaries.isNotEmpty ? _dictionaries.first : null)
        : _dictionaries[_selectedDictionaryIndex]);
    if (dict == null) return null;
    return await _dictionaryQueryService.readMedia(dict, url);
  }

  List<String> _extractSoundUrls(String html) {
    final reg = RegExp(r'sound://[^"\s>]+');
    return reg.allMatches(html).map((m) => m.group(0)!).toList();
  }

  List<String> _extractImageUrls(String html) {
    final reg = RegExp(r'(mdd://|res://)[^"\s>]+');
    return reg.allMatches(html).map((m) => m.group(0)!).toList();
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

  Future<void> _loadDictionaries() async {
    final dictionaries = await _dictionaryService.getDictionaries();
    if (mounted) {
      setState(() {
        _dictionaries = dictionaries;
        if (_dictionaries.isNotEmpty && _selectedDictionaryIndex >= _dictionaries.length) {
          _selectedDictionaryIndex = -1;
        }
      });
    }
  }

  void _doDictionarySearch(String word) async {
    if (_dictionaries.isEmpty || word.isEmpty) {
      return;
    }
    setState(() {
      _isDictionaryLoading = true;
      _dictionarySearchResult = null;
      _dictionarySearchEntries = [];
    });

    if (_selectedDictionaryIndex == -1) {
      final List<_DictKeyItem> entries = [];
      for (final d in _dictionaries) {
        final keys = await _dictionaryQueryService.searchKeys(d, word, limit: 20);
        for (final k in keys) {
          entries.add(_DictKeyItem(d, k));
        }
      }
      if (mounted) {
        setState(() {
          _dictionarySearchEntries = entries;
          _isDictionaryLoading = false;
        });
      }
    } else {
      final dictionary = _dictionaries[_selectedDictionaryIndex];
      final keys = await _dictionaryQueryService.searchKeys(dictionary, word, limit: 50);
      if (mounted) {
        setState(() {
          _dictionarySearchEntries = keys.map((k) => _DictKeyItem(dictionary, k)).toList();
          _isDictionaryLoading = false;
        });
      }
    }
  }

  Future<void> _lookupTargetItem(_DictKeyItem item) async {
    if (_dictionaries.isEmpty) return;
    setState(() {
      _isDictionaryLoading = true;
      _dictionarySearchResult = null;
    });
    final result = await _dictionaryQueryService.lookupWord(item.dictionary, item.key);
    if (mounted) {
      setState(() {
        _dictionarySearchResult = result;
        _dictionarySearchSource = item.dictionary;
        _isDictionaryLoading = false;
      });
    }
  }

  void _changeDictionaryIndex(int? index) {
    setState(() {
      _selectedDictionaryIndex = index ?? -1;
    });
    final text = _dictionarySearchController.text.trim();
    if (text.isNotEmpty) {
      _doDictionarySearch(text);
    }
  }

  Widget _buildDictionaryLookup(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '词典查询',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            if (_dictionaries.isNotEmpty)
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      value: _selectedDictionaryIndex,
                      items: [
                        const DropdownMenuItem<int>(value: -1, child: Text('所有词典')),
                        for (int i = 0; i < _dictionaries.length; i++)
                          DropdownMenuItem<int>(value: i, child: Text(_dictionaries[i].name)),
                      ],
                      onChanged: _changeDictionaryIndex,
                      decoration: const InputDecoration(
                        labelText: '选择词典',
                      ),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 8),
            TextField(
              controller: _dictionarySearchController,
              decoration: InputDecoration(
                hintText: '输入要查询的单词',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () => _doDictionarySearch(_dictionarySearchController.text),
                ),
              ),
              onSubmitted: _doDictionarySearch,
            ),
            if (_isDictionaryLoading)
              const Padding(
                padding: EdgeInsets.all(8.0),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (_dictionarySearchResult != null)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: _buildExplanationHtml(context: context, html: _dictionarySearchResult!),
              ),
            if (_dictionarySearchResult != null)
              Builder(builder: (context) {
                final urls = _extractSoundUrls(_dictionarySearchResult!);
                if (urls.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: urls
                        .map((u) => OutlinedButton.icon(
                              onPressed: () => _playSound(u),
                              icon: const Icon(Icons.play_circle_outline),
                              label: Text('音频'),
                            ))
                        .toList(),
                  ),
                );
              }),
            if (_dictionarySearchResult != null)
              Builder(builder: (context) {
                final urls = _extractImageUrls(_dictionarySearchResult!);
                if (urls.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: urls
                        .map((u) => FutureBuilder<Uint8List?>(
                              future: _loadMedia(u),
                              builder: (context2, snapshot) {
                                if (snapshot.connectionState != ConnectionState.done) {
                                  return const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2));
                                }
                                final bytes = snapshot.data;
                                if (bytes == null || bytes.isEmpty) {
                                  return const SizedBox.shrink();
                                }
                                return Image.memory(bytes, width: 120);
                              },
                            ))
                        .toList(),
                  ),
                );
              }),
            if (_dictionarySearchEntries.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('匹配项', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _dictionarySearchEntries.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        final item = _dictionarySearchEntries[index];
                        return ListTile(
                          dense: true,
                          title: Text(item.key),
                          subtitle: Text(item.dictionary.name),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _lookupTargetItem(item),
                        );
                      },
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  // 不再通过索引推断词义文本，例句标签仅使用例句中存储的 senseText。

  void _showAIGenerateExamplesDialog(Word word) async {
    final req = await showDialog<AIGenerateExamplesRequest>(
      context: context,
      builder: (context) => AIGenerateExamplesDialog(
        initialPrompt: word.prompt,
        initialAnswer: word.answer,
      ),
    );

    if (req == null) return;

    try {
      // 选择生成策略：追加 / 覆盖 / 跳过（若已存在）
      final chosen = await pickAIGenerateExamplesStrategy(context, defaultValue: 'append');

      final svc = ExampleSentenceService();
      if (chosen == 'skip') {
        final existing = await svc.getExamplesByWordId(word.id!);
        if (existing.isNotEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('"${word.prompt}" 已有例句，已跳过')),
            );
          }
          return;
        }
      }

      if (chosen == 'overwrite') {
        await svc.deleteByWordId(word.id!);
      }

      // 线性进度（单词粒度，单个词 total=1）
      final total = 1;
      final progress = ValueNotifier<int>(0);

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('正在生成例句'),
          content: ValueListenableBuilder<int>(
            valueListenable: progress,
            builder: (context, done, _) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(value: total == 0 ? 0 : done / total),
                const SizedBox(height: 8),
                Text('进度：$done / $total'),
              ],
            ),
          ),
        ),
      );

      final ai = await AIExampleService.getInstance();
      final examples = await ai.generateExamples(
        prompt: req.prompt,
        answer: req.answer,
        sourceLanguage: req.sourceLanguage,
        targetLanguage: req.targetLanguage,
      );
      progress.value = 1;

      final withWordId = examples.map((e) => e.copyWith(wordId: word.id)).toList();
      await svc.insertExamples(withWordId);
      await _loadExamples(word: word);

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已为 "${word.prompt}" 生成 ${withWordId.length} 条例句')),
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

  Future<void> _generateExplanation(Word word) async {
    if (word.id == null) return;
    try {
      // 若已存在词解，提供策略选择（覆盖/跳过）
      final existing = await _explanationService.getByWordId(word.id!);
      if (existing != null) {
        final choice = await showDialog<String>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('生成策略'),
                content: const Text('检测到已存在词解，选择是否覆盖或跳过。'),
                actions: [
                  TextButton(onPressed: () => Navigator.of(context).pop('skip'), child: const Text('跳过')),
                  TextButton(onPressed: () => Navigator.of(context).pop('overwrite'), child: const Text('覆盖')),
                ],
              ),
            ) ?? 'skip';
        if (choice == 'skip') {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('"${word.prompt}" 已有词解，已跳过')),
          );
          return;
        }
      }

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

      final ai = await AIWordExplanationService.getInstance();
      final html = await ai.generateExplanationHtml(
        prompt: word.prompt,
        answer: word.answer,
      );

      final now = DateTime.now();
      final exp = WordExplanation(
        id: null,
        wordId: word.id!,
        html: html,
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