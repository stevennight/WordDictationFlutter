import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'dart:typed_data';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_word_dictation/core/models/dictionary.dart';
import 'package:flutter_word_dictation/core/services/dictionary_query_service.dart';

class DictionaryEntryScreen extends StatefulWidget {
  final Dictionary dictionary;
  final String entryKey;

  const DictionaryEntryScreen({super.key, required this.dictionary, required this.entryKey});

  @override
  State<DictionaryEntryScreen> createState() => _DictionaryEntryScreenState();
}

class _DictionaryEntryScreenState extends State<DictionaryEntryScreen> {
  final DictionaryQueryService _queryService = DictionaryQueryService();
  final AudioPlayer _audioPlayer = AudioPlayer();
  String? _html;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadEntry();
  }

  @override
  void dispose() {
    _queryService.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _loadEntry() async {
    setState(() {
      _loading = true;
      _html = null;
    });
    final res = await _queryService.lookupWord(widget.dictionary, widget.entryKey);
    if (mounted) {
      setState(() {
        _html = res;
        _loading = false;
      });
    }
  }

  Widget _buildExplanationHtml(String html) {
    final normalized = html.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
    final plain = normalized.replaceAll(RegExp(r'<[^>]+>'), '');
    return _buildRubyText(normalized, plain);
  }

  Widget _buildRubyText(String html, String plain) {
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
      if (match.start > lastIndex) {
        final before = html.substring(lastIndex, match.start).replaceAll(RegExp(r"<[^>]+>"), "");
        if (before.isNotEmpty) {
          spans.add(TextSpan(text: before, style: baseStyle));
        }
      }

      final rubyBlock = (match.group(1) ?? '').replaceAll(RegExp(r"<rp>[\s\S]*?<\/rp>"), '');

      final rbs = RegExp(r"<rb>([\s\S]*?)<\/rb>").allMatches(rubyBlock).map((m) => m.group(1) ?? '').toList();
      final rts = RegExp(r"<rt>([\s\S]*?)<\/rt>").allMatches(rubyBlock).map((m) => m.group(1) ?? '').toList();

      if (rbs.isEmpty && rts.isEmpty) {
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

    if (lastIndex < html.length) {
      final after = html.substring(lastIndex).replaceAll(RegExp(r"<[^>]+>"), "");
      if (after.isNotEmpty) {
        spans.add(TextSpan(text: after, style: baseStyle));
      }
    }

    return spans;
  }

  List<String> _extractSoundUrls(String html) {
    final reg = RegExp(r'sound://[^"\s>]+');
    return reg.allMatches(html).map((m) => m.group(0)!).toList();
  }

  List<String> _extractImageUrls(String html) {
    final reg = RegExp(r'(mdd://|res://)[^"\s>]+');
    return reg.allMatches(html).map((m) => m.group(0)!).toList();
  }

  Future<void> _playSound(String url) async {
    try {
      final bytes = await _queryService.readMedia(widget.dictionary, url);
      if (bytes == null) return;
      final dir = await getTemporaryDirectory();
      final name = url.split('://').last;
      final matched = _queryService.lastResolvedMediaKey;
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
      await _audioPlayer.stop();
      await _audioPlayer.play(DeviceFileSource(filePath));
    } catch (_) {}
  }

  Future<Uint8List?> _loadMedia(String url) async {
    return await _queryService.readMedia(widget.dictionary, url);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.entryKey} - ${widget.dictionary.name}'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_html == null)
              ? Center(
                  child: Text(
                    '未找到词条',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: _buildExplanationHtml(_html!),
                        ),
                      ),
                      Builder(builder: (context) {
                        final urls = _extractSoundUrls(_html!);
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
                                      label: const Text('音频'),
                                    ))
                                .toList(),
                          ),
                        );
                      }),
                      Builder(builder: (context) {
                        final urls = _extractImageUrls(_html!);
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
                    ],
                  ),
                ),
    );
  }
}