import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'dart:typed_data';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_word_dictation/core/models/dictionary.dart';
import 'package:flutter_word_dictation/core/services/dictionary_query_service.dart';
import 'package:flutter_html/flutter_html.dart';

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
    final len = res?.length ?? 0;
    final preview = () {
      final s = (res ?? '').replaceAll(RegExp(r'\s+'), ' ');
      return s.length > 200 ? s.substring(0, 200) : s;
    }();
    print('[DictEntry] lookup: dict=' + widget.dictionary.name + ' key="' + widget.entryKey + '" len=' + len.toString() + ' preview="' + preview + '"');
    if (res != null) {
      final classes = <String>{};
      for (final m in RegExp(r'class\s*=\s*"([^"]+)"').allMatches(res)) {
        final parts = (m.group(1) ?? '').split(RegExp(r'\s+')).where((e) => e.trim().isNotEmpty);
        classes.addAll(parts);
      }
      if (classes.isNotEmpty) {
        final first = classes.take(16).join(', ');
        print('[DictEntry] classes: ' + first + (classes.length > 16 ? ' ...' : ''));
      }
    }
    if (mounted) {
      setState(() {
        _html = res;
        _loading = false;
      });
    }
  }

  String _prepareHtml(String html) {
    var s = html;
    s = _bodyOnly(s);
    s = _heuristicBlockify(s);
    s = s.replaceAll(RegExp(r'color\s*:\s*(black|#000000|#000|rgb\(\s*0\s*,\s*0\s*,\s*0\s*\))', caseSensitive: false), 'color: inherit');
    s = s.replaceAll(RegExp(r'color\s*:\s*(black|#000000|#000|rgb\(\s*0\s*,\s*0\s*,\s*0\s*\))', caseSensitive: false), 'color: inherit');
    s = s.replaceAll(RegExp(r'<font([^>]*?)\scolor\s*=\s*"[^"]*"', caseSensitive: false), '<font');
    s = s.replaceAll(RegExp(r"<font([^>]*?)\scolor\s*=\s*'[^']*'", caseSensitive: false), '<font');
    s = s.replaceAll(RegExp(r'<style[\s\S]*?<\/style>', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'<script[\s\S]*?<\/script>', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'<link[^>]*rel\s*=\s*"stylesheet"[^>]*>', caseSensitive: false), '');
    return s;
  }

  String _bodyOnly(String s) {
    var out = s.replaceFirst(RegExp(r'^\s*<\?xml[\s\S]*?\?>', multiLine: true), '');
    final m = RegExp(r'<body[^>]*>([\s\S]*?)<\/body>', caseSensitive: false).firstMatch(out);
    if (m != null) {
      return m.group(1) ?? out;
    }
    out = out.replaceAll(RegExp(r'<head[\s\S]*?<\/head>', caseSensitive: false), '');
    out = out.replaceAll(RegExp(r'<html[^>]*>', caseSensitive: false), '');
    out = out.replaceAll(RegExp(r'<\/html>', caseSensitive: false), '');
    return out;
  }

  String _heuristicBlockify(String s) {
    var out = s;
    out = out.replaceAllMapped(RegExp(r'【([^】]+)】'), (match) => '<h3>' + match.group(1)!.trim() + '</h3>');
    out = out.replaceAllMapped(RegExp(r'([★◆◎●○◇■□▲△※])'), (m) => '<br/>' + m.group(1)!);
    out = out.replaceAllMapped(RegExp(r'([①②③④⑤⑥⑦⑧⑨⑩])'), (m) => '<br/>' + m.group(1)!);
    out = out.replaceAll(RegExp(r'\s・'), '<br/>・');
    return out;
  }

  String _stripEntities(String s) {
    return s
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&');
  }

  Widget _buildExplanationHtml(String html) {
    final theme = Theme.of(context);
    final prepared = _prepareHtml(html);
    final plain = _stripEntities(prepared.replaceAll(RegExp(r'<[^>]+>'), ' ')).trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Html(
          data: prepared,
          style: {
            'html': Style(color: theme.colorScheme.onSurface),
            'body': Style(
              fontSize: FontSize(theme.textTheme.bodyLarge?.fontSize ?? 16),
              lineHeight: const LineHeight(1.6),
              color: theme.colorScheme.onSurface,
            ),
            'p': Style(margin: Margins.symmetric(vertical: 8)),
            'div': Style(margin: Margins.symmetric(vertical: 6)),
            'h1': Style(fontSize: FontSize(24), fontWeight: FontWeight.bold, margin: Margins.only(bottom: 8)),
            'h2': Style(fontSize: FontSize(22), fontWeight: FontWeight.bold, margin: Margins.only(bottom: 8)),
            'h3': Style(fontSize: FontSize(20), fontWeight: FontWeight.bold, margin: Margins.only(bottom: 8)),
            'ul': Style(margin: Margins.symmetric(vertical: 6), padding: HtmlPaddings.only(left: 20)),
            'ol': Style(margin: Margins.symmetric(vertical: 6), padding: HtmlPaddings.only(left: 20)),
            'li': Style(margin: Margins.only(bottom: 4)),
            'blockquote': Style(
              margin: Margins.symmetric(vertical: 8),
              padding: HtmlPaddings.symmetric(horizontal: 12, vertical: 8),
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
            'code': Style(
              fontFamily: 'monospace',
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              padding: HtmlPaddings.symmetric(horizontal: 6, vertical: 4),
            ),
            'pre': Style(
              fontFamily: 'monospace',
              whiteSpace: WhiteSpace.pre,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              padding: HtmlPaddings.all(8),
            ),
            'table': Style(margin: Margins.only(top: 8)),
            'th': Style(fontWeight: FontWeight.bold, padding: HtmlPaddings.all(6), backgroundColor: theme.colorScheme.surfaceContainerHighest),
            'td': Style(padding: HtmlPaddings.all(6)),
            'ruby': Style(fontWeight: FontWeight.w600),
            'rt': Style(fontSize: FontSize((theme.textTheme.bodySmall?.fontSize ?? 12) * 0.9), color: theme.colorScheme.onSurfaceVariant),
            'span': Style(color: theme.colorScheme.onSurface),
            'a': Style(color: theme.colorScheme.primary),
          },
          extensions: [
            TagExtension(tagsToExtend: {'ruby'}, builder: (context) {
              final el = context.element;
              final children = el?.children ?? const [];
              final rbs = <String>[];
              final rts = <String>[];
              for (final c in children) {
                final name = (c.localName ?? '').toLowerCase();
                final text = c.text.trim();
                if (name == 'rb') {
                  rbs.add(text);
                } else if (name == 'rt') {
                  rts.add(text);
                }
              }
              final theme2 = Theme.of(context.buildContext!);
              final baseStyle = theme2.textTheme.bodyLarge;
              final rubyStyle = theme2.textTheme.bodySmall?.copyWith(color: theme2.colorScheme.onSurfaceVariant);
              return Wrap(
                spacing: 4,
                runSpacing: 2,
                crossAxisAlignment: WrapCrossAlignment.end,
                children: [
                  for (int i = 0; i < (rbs.length > rts.length ? rbs.length : rts.length); i++)
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        if (i < rts.length && rts[i].isNotEmpty) Text(rts[i], style: rubyStyle),
                        if (i < rbs.length && rbs[i].isNotEmpty) Text(rbs[i], style: baseStyle),
                      ],
                    ),
                ],
              );
            }),
          ],
        ),
        if (plain.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            plain,
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ],
    );
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