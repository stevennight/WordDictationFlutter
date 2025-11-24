import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Renders word explanation from JSON data structure
class WordExplanationRenderer extends StatelessWidget {
  final String jsonData;
  final String? sourceLanguage;

  const WordExplanationRenderer({
    super.key,
    required this.jsonData,
    this.sourceLanguage,
  });

  @override
  Widget build(BuildContext context) {
    Map<String, dynamic> data;
    try {
      debugPrint('[Renderer] Parsing JSON data...');
      debugPrint('[Renderer] JSON length: ${jsonData.length}');
      debugPrint('[Renderer] JSON preview: ${jsonData.substring(0, jsonData.length > 200 ? 200 : jsonData.length)}');
      data = jsonDecode(jsonData) as Map<String, dynamic>;
      debugPrint('[Renderer] JSON parsed successfully');
    } catch (e) {
      debugPrint('[Renderer] JSON parse error: $e');
      debugPrint('[Renderer] Failed JSON: $jsonData');
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '解析错误',
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '错误详情: $e',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
        ],
      );
    }

    // Infer language from JSON metadata if not provided
    final inferredLanguage = sourceLanguage ?? _inferLanguageFromJson(data);
    final sourceIsJa = _isJapanese(inferredLanguage);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Definition section
        _buildDefinition(context, data, sourceIsJa),
        
        // Highlights section
        if (_hasHighlights(data)) ...[
          const SizedBox(height: 16),
          _buildHighlights(context, data, sourceIsJa),
        ],
        
        // Synonyms section
        if (_hasSynonyms(data)) ...[
          const SizedBox(height: 16),
          _buildSynonyms(context, data, sourceIsJa),
        ],
        
        // Antonyms section
        if (_hasAntonyms(data)) ...[
          const SizedBox(height: 16),
          _buildAntonyms(context, data, sourceIsJa),
        ],
        
        // Extras section
        if (_hasExtras(data)) ...[
          const SizedBox(height: 16),
          _buildExtras(context, data, sourceIsJa),
        ],
        
        // Examples section (at bottom)
        if (_hasExamples(data)) ...[
          const SizedBox(height: 24),
          _buildExamples(context, data, sourceIsJa),
        ],
        
        // Sources section
        if (_hasSources(data)) ...[
          const SizedBox(height: 16),
          _buildSources(context, data),
        ],
      ],
    );
  }

  bool _isJapanese(String? lang) {
    if (lang == null) return false;
    final normalized = lang.trim().toLowerCase();
    return normalized == 'ja' || normalized == 'jp' || normalized == 'japanese';
  }

  String? _inferLanguageFromJson(Map<String, dynamic> data) {
    // Check if any content contains ruby tags (Japanese indicator)
    final def = _getMap(data, 'definition');
    final collocations = _getList(def, 'collocations');
    
    for (final colloc in collocations) {
      final collocMap = colloc as Map<String, dynamic>;
      final textHtml = _getString(collocMap, 'textHtml');
      if (textHtml.contains('<ruby>')) {
        return 'ja';
      }
    }
    
    // Check synonyms
    final synonyms = _getList(data, 'synonyms');
    for (final syn in synonyms) {
      final synMap = syn as Map<String, dynamic>;
      final termHtml = _getString(synMap, 'termHtml');
      if (termHtml.contains('<ruby>')) {
        return 'ja';
      }
    }
    
    return null;
  }

  Widget _buildDefinition(BuildContext context, Map<String, dynamic> data, bool sourceIsJa) {
    // Parse nested structure: definition.senses, definition.pronunciation, definition.collocations
    final def = _getMap(data, 'definition');
    final senses = _getList(def, 'senses');
    final pronunciation = _getMap(def, 'pronunciation');
    final collocations = _getList(def, 'collocations');

    // Debug output
    debugPrint('[Renderer] ========== JSON Structure ==========');
    debugPrint('[Renderer] Root keys: ${data.keys.toList()}');
    debugPrint('[Renderer] definition keys: ${def.keys.toList()}');
    debugPrint('[Renderer] senses count: ${senses.length}');
    if (senses.isNotEmpty) {
      debugPrint('[Renderer] First sense: ${senses[0]}');
    }
    debugPrint('[Renderer] pronunciation: ${pronunciation.isNotEmpty}');
    if (pronunciation.isNotEmpty) {
      debugPrint('[Renderer] pronunciation text: ${_getString(pronunciation, 'text')}');
    }
    debugPrint('[Renderer] collocations count: ${collocations.length}');
    debugPrint('[Renderer] =====================================');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Pronunciation
        if (pronunciation.isNotEmpty && _getString(pronunciation, 'text').isNotEmpty) ...[
          Row(
            children: [
              Icon(
                Icons.record_voice_over,
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                '发音',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _getString(pronunciation, 'text'),
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],

        // Senses
        if (senses.isNotEmpty) ...[
          ...senses.map((sense) {
            final senseMap = sense as Map<String, dynamic>;
            final pos = _getString(senseMap, 'pos');
            final text = _getString(senseMap, 'text');
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (pos.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      margin: const EdgeInsets.only(right: 8, top: 2),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        pos,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  Expanded(
                    child: _buildRichText(
                      context,
                      text,
                      sourceIsJa: sourceIsJa,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ],

        // Collocations
        if (collocations.isNotEmpty) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                Icons.auto_awesome,
                size: 18,
                color: Theme.of(context).colorScheme.secondary,
              ),
              const SizedBox(width: 8),
              Text(
                '常用搭配',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.secondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...collocations.map((colloc) {
            final collocMap = colloc as Map<String, dynamic>;
            final textHtml = _getString(collocMap, 'textHtml');
            final translation = _getString(collocMap, 'translation');
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 4, right: 8),
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.secondary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildRichText(
                          context,
                          textHtml,
                          sourceIsJa: sourceIsJa,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                        if (translation.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            translation,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ],
    );
  }

  Widget _buildExamples(BuildContext context, Map<String, dynamic> data, bool sourceIsJa) {
    final examples = _getList(data, 'examples');
    if (examples.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.format_quote,
              size: 18,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text(
              '例句',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...examples.asMap().entries.map((entry) {
          final index = entry.key;
          final example = entry.value as Map<String, dynamic>;
          final senseText = _getString(example, 'senseText');
          final textHtml = _getString(example, 'textHtml');
          final textTranslation = _getString(example, 'textTranslation');
          final grammarNotes = _getList(example, 'grammarNotes');

          return Padding(
            padding: EdgeInsets.only(bottom: index < examples.length - 1 ? 16 : 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (senseText.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      senseText,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                _buildRichText(
                  context,
                  textHtml,
                  sourceIsJa: sourceIsJa,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                if (textTranslation.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    textTranslation,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (grammarNotes.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ...grammarNotes.map((note) {
                    final noteStr = note is String ? note : note.toString();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            margin: const EdgeInsets.only(top: 6, right: 8),
                            width: 4,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.tertiary,
                              shape: BoxShape.circle,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              noteStr,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ],
              ],
            ),
          );
        }).toList(),
      ],
    );
  }

  Widget _buildHighlights(BuildContext context, Map<String, dynamic> data, bool sourceIsJa) {
    final highlights = _getList(data, 'highlights');
    if (highlights.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.lightbulb_outline,
              size: 18,
              color: Theme.of(context).colorScheme.tertiary,
            ),
            const SizedBox(width: 8),
            Text(
              '重点提示',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.tertiary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...highlights.map((highlight) {
          final highlightMap = highlight as Map<String, dynamic>;
          final textHtml = _getString(highlightMap, 'textHtml');
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('• ', style: Theme.of(context).textTheme.bodyLarge),
                Expanded(
                  child: _buildRichText(
                    context,
                    textHtml,
                    sourceIsJa: sourceIsJa,
                    translation: true,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ],
    );
  }

  Widget _buildSynonyms(BuildContext context, Map<String, dynamic> data, bool sourceIsJa) {
    final synonyms = _getList(data, 'synonyms');
    if (synonyms.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.compare_arrows,
              size: 18,
              color: Theme.of(context).colorScheme.secondary,
            ),
            const SizedBox(width: 8),
            Text(
              '近义词',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.secondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...synonyms.map((syn) {
          final synMap = syn as Map<String, dynamic>;
          final termHtml = _getString(synMap, 'termHtml');
          final gloss = _getString(synMap, 'gloss');
          final differenceHtml = _getString(synMap, 'differenceHtml');
          final selfHtml = _getString(synMap, 'selfHtml');
          final selfTranslation = _getString(synMap, 'selfTranslation');
          final synHtml = _getString(synMap, 'synHtml');
          final synTranslation = _getString(synMap, 'synTranslation');

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _buildRichText(
                      context,
                      termHtml,
                      sourceIsJa: sourceIsJa,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (gloss.isNotEmpty) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          gloss,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (differenceHtml.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  _buildRichText(
                    context,
                    differenceHtml,
                    sourceIsJa: sourceIsJa,
                    translation: true,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ],
                if (selfHtml.isNotEmpty || synHtml.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  if (selfHtml.isNotEmpty)
                    _buildExampleRow(context, selfHtml, selfTranslation, sourceIsJa),
                  if (synHtml.isNotEmpty)
                    _buildExampleRow(context, synHtml, synTranslation, sourceIsJa),
                ],
              ],
            ),
          );
        }).toList(),
      ],
    );
  }

  Widget _buildAntonyms(BuildContext context, Map<String, dynamic> data, bool sourceIsJa) {
    final antonyms = _getList(data, 'antonyms');
    if (antonyms.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.swap_horiz,
              size: 18,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(width: 8),
            Text(
              '反义词',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...antonyms.map((ant) {
          final antMap = ant as Map<String, dynamic>;
          final termHtml = _getString(antMap, 'termHtml');
          final gloss = _getString(antMap, 'gloss');
          final exampleHtml = _getString(antMap, 'exampleHtml');
          final exampleTranslation = _getString(antMap, 'exampleTranslation');

          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _buildRichText(
                      context,
                      termHtml,
                      sourceIsJa: sourceIsJa,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (gloss.isNotEmpty) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          gloss,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (exampleHtml.isNotEmpty)
                  _buildExampleRow(context, exampleHtml, exampleTranslation, sourceIsJa),
              ],
            ),
          );
        }).toList(),
      ],
    );
  }

  Widget _buildExtras(BuildContext context, Map<String, dynamic> data, bool sourceIsJa) {
    final extras = _getList(data, 'extras');
    if (extras.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.info_outline,
              size: 18,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text(
              '补充说明',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...extras.map((extra) {
          final extraMap = extra as Map<String, dynamic>;
          final textHtml = _getString(extraMap, 'textHtml');
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('• ', style: Theme.of(context).textTheme.bodyLarge),
                Expanded(
                  child: _buildRichText(
                    context,
                    textHtml,
                    sourceIsJa: sourceIsJa,
                    translation: true,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ],
    );
  }

  Widget _buildExampleRow(BuildContext context, String exampleHtml, String translation, bool sourceIsJa) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildRichText(
            context,
            exampleHtml,
            sourceIsJa: sourceIsJa,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          if (translation.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              translation,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRichText(
    BuildContext context,
    String html, {
    bool sourceIsJa = false,
    bool translation = false,
    TextStyle? style,
  }) {
    final cleaned = _cleanRubyTags(html, sourceIsJa: sourceIsJa, translation: translation);
    
    // Check if there are ruby tags
    if (cleaned.contains('<ruby>')) {
      return _RubyTextWidget(
        html: cleaned,
        style: style ?? Theme.of(context).textTheme.headlineSmall!,
        rubyColor: Theme.of(context).colorScheme.onSurfaceVariant,
      );
    }
    
    // No ruby tags, use simple text
    return Text(
      _stripHtmlTags(cleaned),
      style: style ?? Theme.of(context).textTheme.headlineSmall,
    );
  }

  String _cleanRubyTags(String html, {bool sourceIsJa = false, bool translation = false}) {
    if (html.trim().isEmpty) return html;
    
    // With AI reflection enabled, ruby tags should be correct
    // Just keep them as-is for Japanese content, remove for non-Japanese
    if (sourceIsJa) {
      return html; // Keep all ruby tags for Japanese
    }
    
    // For non-Japanese content, strip ruby tags (backward compatibility)
    final rubyRegex = RegExp(r'<ruby><rb>(.*?)</rb><rt>.*?</rt></ruby>');
    return html.replaceAllMapped(rubyRegex, (match) {
      return match.group(1) ?? ''; // Return only base text
    });
  }

  String _stripHtmlTags(String html) {
    return html.replaceAll(RegExp(r'<[^>]+>'), '');
  }

  Widget _buildSources(BuildContext context, Map<String, dynamic> data) {
    final sources = _getList(data, 'sources');
    if (sources.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Divider(color: Theme.of(context).colorScheme.outlineVariant),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(
              Icons.source_outlined,
              size: 18,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Text(
              '参考来源',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ...sources.map((source) {
          final sourceMap = source as Map<String, dynamic>;
          final dictionary = _getString(sourceMap, 'dictionary');
          final key = _getString(sourceMap, 'key');
          return Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(
              '$dictionary：$key',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          );
        }).toList(),
      ],
    );
  }

  bool _hasExamples(Map<String, dynamic> data) => _getList(data, 'examples').isNotEmpty;
  bool _hasHighlights(Map<String, dynamic> data) => _getList(data, 'highlights').isNotEmpty;
  bool _hasSynonyms(Map<String, dynamic> data) => _getList(data, 'synonyms').isNotEmpty;
  bool _hasAntonyms(Map<String, dynamic> data) => _getList(data, 'antonyms').isNotEmpty;
  bool _hasExtras(Map<String, dynamic> data) => _getList(data, 'extras').isNotEmpty;
  bool _hasSources(Map<String, dynamic> data) => _getList(data, 'sources').isNotEmpty;

  Map<String, dynamic> _getMap(Map<String, dynamic> data, String key) {
    final value = data[key];
    return value is Map<String, dynamic> ? value : {};
  }

  List<dynamic> _getList(Map<String, dynamic> data, String key) {
    final value = data[key];
    return value is List ? value : [];
  }

  String _getString(Map<String, dynamic> data, String key) {
    final value = data[key];
    return value is String ? value.trim() : '';
  }
}

/// Custom widget for rendering ruby text with proper alignment
class _RubyTextWidget extends StatelessWidget {
  final String html;
  final TextStyle style;
  final Color rubyColor;

  const _RubyTextWidget({
    required this.html,
    required this.style,
    required this.rubyColor,
  });

  @override
  Widget build(BuildContext context) {
    final segments = _parseRubySegments(html);
    
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.end,
      children: segments.map((segment) {
        if (segment.isRuby) {
          return _RubyCharacter(
            base: segment.base,
            ruby: segment.ruby,
            baseStyle: style,
            rubyStyle: style.copyWith(
              fontSize: (style.fontSize ?? 24) * 0.5,
              color: rubyColor,
              height: 1.0,
            ),
          );
        } else {
          return Text(segment.base, style: style);
        }
      }).toList(),
    );
  }

  List<_RubySegment> _parseRubySegments(String html) {
    final segments = <_RubySegment>[];
    final rubyRegex = RegExp(r'<ruby><rb>(.*?)</rb><rt>(.*?)</rt></ruby>');
    
    int lastEnd = 0;
    for (final match in rubyRegex.allMatches(html)) {
      if (match.start > lastEnd) {
        final text = html.substring(lastEnd, match.start);
        final cleaned = text.replaceAll(RegExp(r'<[^>]+>'), '');
        if (cleaned.isNotEmpty) {
          segments.add(_RubySegment(base: cleaned, ruby: '', isRuby: false));
        }
      }
      
      final base = match.group(1) ?? '';
      final ruby = match.group(2) ?? '';
      segments.add(_RubySegment(base: base, ruby: ruby, isRuby: true));
      
      lastEnd = match.end;
    }
    
    if (lastEnd < html.length) {
      final text = html.substring(lastEnd);
      final cleaned = text.replaceAll(RegExp(r'<[^>]+>'), '');
      if (cleaned.isNotEmpty) {
        segments.add(_RubySegment(base: cleaned, ruby: '', isRuby: false));
      }
    }
    
    return segments;
  }
}

class _RubySegment {
  final String base;
  final String ruby;
  final bool isRuby;

  _RubySegment({required this.base, required this.ruby, required this.isRuby});
}

class _RubyCharacter extends StatelessWidget {
  final String base;
  final String ruby;
  final TextStyle baseStyle;
  final TextStyle rubyStyle;

  const _RubyCharacter({
    required this.base,
    required this.ruby,
    required this.baseStyle,
    required this.rubyStyle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(ruby, style: rubyStyle),
        Text(base, style: baseStyle),
      ],
    );
  }
}
