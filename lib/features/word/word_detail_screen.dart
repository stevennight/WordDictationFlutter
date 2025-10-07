import 'package:flutter/material.dart';
import 'package:flutter_word_dictation/shared/models/word.dart';
import 'package:flutter_word_dictation/core/services/example_sentence_service.dart';
import 'package:flutter_word_dictation/shared/models/example_sentence.dart';
import 'package:flutter_word_dictation/core/services/ai_example_service.dart';
import 'package:flutter_word_dictation/shared/widgets/ai_generate_examples_dialog.dart';
import 'package:flutter_word_dictation/shared/widgets/ai_generate_examples_strategy_dialog.dart';

class WordDetailScreen extends StatefulWidget {
  final Word word;

  const WordDetailScreen({super.key, required this.word});

  @override
  State<WordDetailScreen> createState() => _WordDetailScreenState();
}

class _WordDetailScreenState extends State<WordDetailScreen> {
  final ExampleSentenceService _exampleService = ExampleSentenceService();
  List<ExampleSentence> _examples = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadExamples();
  }

  Future<void> _loadExamples() async {
    if (widget.word.id != null) {
      final data = await _exampleService.getExamplesByWordId(widget.word.id!);
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

  @override
  Widget build(BuildContext context) {
    final word = widget.word;
    return Scaffold(
      appBar: AppBar(
        title: Text(word.prompt),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 基本信息
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
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.icon(
                          onPressed: () => _showAIGenerateExamplesDialog(word),
                          icon: const Icon(Icons.auto_awesome),
                          label: const Text('AI生成例句'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // 例句列表
            Text(
              '例句',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (_loading)
              const Center(child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              ))
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
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                          ),
                          if (ex.grammarNote.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              ex.grammarNote,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
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

      final rubyBlock = (match.group(1) ?? '')
          .replaceAll(RegExp(r"<rp>[\s\S]*?<\/rp>"), '');

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
      await _loadExamples();

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
}
// 移至文件顶部统一导入（见上），删除中部重复导入