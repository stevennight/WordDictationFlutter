import 'package:flutter/material.dart';
import 'package:flutter_word_dictation/shared/models/word.dart';
import 'package:flutter_word_dictation/core/services/example_sentence_service.dart';
import 'package:flutter_word_dictation/shared/models/example_sentence.dart';

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
            Card(
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
                  ],
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
                              Text('含义 ${ex.senseIndex + 1}', style: Theme.of(context).textTheme.bodySmall),
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

      final rubyBlock = match.group(1) ?? '';
      final rb = RegExp(r"<rb>([\s\S]*?)<\/rb>").firstMatch(rubyBlock)?.group(1) ?? '';
      final rt = RegExp(r"<rt>([\s\S]*?)<\/rt>").firstMatch(rubyBlock)?.group(1) ?? '';

      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (rt.isNotEmpty)
                  Text(rt, style: rubyStyle, textAlign: TextAlign.center),
                if (rb.isNotEmpty)
                  Text(rb, style: baseStyle, textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      );

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
}