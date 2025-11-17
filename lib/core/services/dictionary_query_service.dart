import 'package:dict_reader/dict_reader.dart';
import 'package:flutter_word_dictation/core/models/dictionary.dart';
import 'dart:typed_data';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'config_service.dart';
import '../mdict/mdd_reader.dart';

class DictionaryQueryService {
  final Map<String, DictReader> _readerCache = {};
  final Map<String, List<RecordOffsetInfo>> _offsetCache = {};
  final Map<String, MddReader> _mddReaderCache = {};
  final Map<String, Map<String, String>> _mddIndexCache = {};
  final Set<String> _mddRootPrinted = {};
  final Map<String, List<String>> _mddHeadsCache = {};
  String? lastResolvedMediaKey;

  Future<String?> lookupWord(Dictionary dictionary, String word) async {
    try {
      var reader = _readerCache[dictionary.path];
      if (reader == null) {
        reader = DictReader(dictionary.path);
        await reader.init();
        _readerCache[dictionary.path] = reader;
        print('[DictionaryQuery] init reader: ${dictionary.name} (${dictionary.path})');
      }

      print('[DictionaryQuery] locate("$word")');
      final offsetInfo = await reader.locate(word);
      if (offsetInfo != null) {
        print('[DictionaryQuery] locate hit: ${offsetInfo.keyText}');
        final content = await reader.readOneMdx(offsetInfo);
        return await _resolveLink(reader, content, dictionaryPath: dictionary.path, expectedTerms: _buildTerms(word));
      }
      print('[DictionaryQuery] locate miss for "$word"');
      // Try soft variants for common dictionary key formats
      final variants = <String>{};
      final raw = word.trim();
      variants.add(raw);
      variants.add(raw.replaceAll(RegExp(r'【[^】]*】'), ''));
      variants.add(raw.replaceAll(RegExp(r'[‐‑–—\-]'), ''));
      variants.add(raw.replaceAll('・', '').replaceAll('·', ''));
      for (final v in variants) {
        final vv = v.trim();
        if (vv.isEmpty || vv == raw) continue;
        final alt = await reader.locate(vv);
        if (alt != null) {
          print('[DictionaryQuery] locate soft hit: $vv');
          final content = await reader.readOneMdx(alt);
          return await _resolveLink(reader, content, dictionaryPath: dictionary.path, expectedTerms: _buildTerms(word));
        }
      }
    } catch (e) {
      _readerCache.remove(dictionary.path);
      print('[DictionaryQuery] error: $e');
    }
    return null;
  }

  Set<String> _buildTerms(String word) {
    final s = word.trim();
    final set = <String>{};
    if (s.isNotEmpty) {
      set.add(s);
      set.add(s.replaceAll('‐', '').replaceAll('‑', '').replaceAll('–', '').replaceAll('—', '').replaceAll('-', ''));
      set.add(s.replaceAll('・', '').replaceAll('·', ''));
      set.add(_toKatakana(s));
      set.add(_toHiragana(s));
    }
    return set;
  }

  bool _contentMatches(String html, Set<String> terms) {
    if (html.isEmpty) return false;
    for (final t in terms) {
      final v1 = t.trim();
      if (v1.isEmpty) continue;
      if (html.contains(v1)) return true;
      final v2 = v1.replaceAll('‐', '').replaceAll('‑', '').replaceAll('–', '').replaceAll('—', '').replaceAll('-', '');
      if (v2.isNotEmpty && html.contains(v2)) return true;
      final v3 = v1.replaceAll('・', '').replaceAll('·', '');
      if (v3.isNotEmpty && html.contains(v3)) return true;
      final v4 = _toKatakana(v1);
      if (v4.isNotEmpty && html.contains(v4)) return true;
      final v5 = _toHiragana(v1);
      if (v5.isNotEmpty && html.contains(v5)) return true;
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

  Future<String?> _resolveLink(
    DictReader reader,
    String? content, {
    required String dictionaryPath,
    int depth = 0,
    Set<String>? expectedTerms,
  }) async {
    if (content == null) return null;
    if (!content.startsWith('@@@LINK=')) return content;
    if (depth > 5) return null;

    final target = content.substring('@@@LINK='.length).trim();
    print('[DictionaryQuery] link detected: $target (depth=$depth)');
    final numeric = _parseNumeric(target);
    print('[DictionaryQuery] numeric parse: ${numeric ?? 'null'}');
    if (numeric != null) {
      print('[DictionaryQuery] numeric link -> index $numeric');
      final info = await _getOffsetByIndex(reader, dictionaryPath, numeric);
      if (info == null) {
        print('[DictionaryQuery] numeric link miss: $numeric');
        final data = await _getDataByIndex(reader, dictionaryPath, numeric);
        if (data != null) {
          if (expectedTerms != null && !_contentMatches(data, expectedTerms)) {
            for (int i = -3; i <= 3; i++) {
              if (i == 0) continue;
              final altData2 = await _getDataByIndex(reader, dictionaryPath, numeric + i);
              if (altData2 != null && _contentMatches(altData2, expectedTerms)) {
                return await _resolveLink(reader, altData2, dictionaryPath: dictionaryPath, depth: depth + 1, expectedTerms: expectedTerms);
              }
            }
          }
          return await _resolveLink(reader, data, dictionaryPath: dictionaryPath, depth: depth + 1, expectedTerms: expectedTerms);
        }
        final alt = numeric + 1;
        print('[DictionaryQuery] try alt index: $alt');
        final altInfo = await _getOffsetByIndex(reader, dictionaryPath, alt);
        if (altInfo != null) {
          final nextAlt = await reader.readOneMdx(altInfo);
          return await _resolveLink(reader, nextAlt, dictionaryPath: dictionaryPath, depth: depth + 1, expectedTerms: expectedTerms);
        }
        final altData = await _getDataByIndex(reader, dictionaryPath, alt);
        if (altData != null) {
          return await _resolveLink(reader, altData, dictionaryPath: dictionaryPath, depth: depth + 1, expectedTerms: expectedTerms);
        }
        return null;
      }
      final next = await reader.readOneMdx(info);
      if (expectedTerms != null && !_contentMatches(next, expectedTerms)) {
        for (int i = -3; i <= 3; i++) {
          if (i == 0) continue;
          final altInfo2 = await _getOffsetByIndex(reader, dictionaryPath, numeric + i);
          if (altInfo2 != null) {
            final altNext2 = await reader.readOneMdx(altInfo2);
            if (_contentMatches(altNext2, expectedTerms)) {
              return await _resolveLink(reader, altNext2, dictionaryPath: dictionaryPath, depth: depth + 1, expectedTerms: expectedTerms);
            }
          }
        }
      }
      return await _resolveLink(reader, next, dictionaryPath: dictionaryPath, depth: depth + 1, expectedTerms: expectedTerms);
    }

    final info = await reader.locate(target);
    if (info == null) return null;
    final next = await reader.readOneMdx(info);
    return await _resolveLink(reader, next, dictionaryPath: dictionaryPath, depth: depth + 1, expectedTerms: expectedTerms);
  }

  int? _parseNumeric(String raw) {
    final ascii = raw
        .replaceAll('\u00A0', '')
        .replaceAll('\u3000', '')
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll('０', '0')
        .replaceAll('１', '1')
        .replaceAll('２', '2')
        .replaceAll('３', '3')
        .replaceAll('４', '4')
        .replaceAll('５', '5')
        .replaceAll('６', '6')
        .replaceAll('７', '7')
        .replaceAll('８', '8')
        .replaceAll('９', '9');
    final digits = ascii.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return null;
    return int.tryParse(digits);
  }

  Future<RecordOffsetInfo?> _getOffsetByIndex(
    DictReader reader,
    String path,
    int index,
  ) async {
    final list = _offsetCache.putIfAbsent(path, () => <RecordOffsetInfo>[]);
    if (index <= list.length) {
      return list[index - 1];
    }
    print('[DictionaryQuery] build offset cache up to $index');
    int i = 0;
    await for (final info in reader.readWithOffset()) {
      i++;
      if (i > list.length) {
        list.add(info);
      }
      if (i == index) {
        return info;
      }
    }
    return null;
  }

  Future<String?> _getDataByIndex(
    DictReader reader,
    String path,
    int index,
  ) async {
    int i = 0;
    await for (final rec in reader.readWithMdxData()) {
      i++;
      if (i == index) {
        return rec.data;
      }
    }
    return null;
  }

  Future<List<String>> searchKeys(Dictionary dictionary, String query, {int limit = 20}) async {
    try {
      var reader = _readerCache[dictionary.path];
      if (reader == null) {
        reader = DictReader(dictionary.path);
        await reader.init();
        _readerCache[dictionary.path] = reader;
        print('[DictionaryQuery] init reader: ${dictionary.name} (${dictionary.path})');
      }
      final keys = reader.search(query, limit: limit);
      print('[DictionaryQuery] search("$query") -> ${keys.length}');
      return keys;
    } catch (e) {
      _readerCache.remove(dictionary.path);
      print('[DictionaryQuery] search error: $e');
      return [];
    }
  }

  Future<Uint8List?> readMedia(Dictionary dictionary, String url) async {
    try {
      final lowerAll = url.toLowerCase();
      if (lowerAll.startsWith('http://') || lowerAll.startsWith('https://')) {
        try {
          final resp = await http.get(Uri.parse(url));
          if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
            print('[DictionaryQuery] http media fetch: ${resp.bodyBytes.length} bytes from $url');
            return resp.bodyBytes;
          }
        } catch (_) {}
      }
      // scheme-based media base mapping
      final idx = lowerAll.indexOf('://');
      if (idx > 0) {
        final scheme = lowerAll.substring(0, idx);
        final pathPart = url.substring(idx + 3);
        final cfg = await ConfigService.getInstance();
        final base = await cfg.getMediaBaseForScheme(scheme);
        if (base != null && base.isNotEmpty) {
          final composed = base.endsWith('/') ? (base + pathPart) : (base + '/' + pathPart);
          try {
            final resp = await http.get(Uri.parse(composed));
            if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
              print('[DictionaryQuery] http media via mapping: ${resp.bodyBytes.length} bytes from $composed');
              return resp.bodyBytes;
            }
          } catch (_) {}
        }
      }
      // Heuristic file lookup for sound:// or res://
      final lower = lowerAll;
      if (lower.startsWith('sound://') || lower.startsWith('res://') || lower.startsWith('mdd://')) {
        final rawName = url.split('://').last;
        final fileName = Uri.decodeComponent(rawName);
        final fileNameLower = fileName.toLowerCase();
        final mdxPath = dictionary.path;
        final dir = mdxPath.substring(0, mdxPath.lastIndexOf(RegExp(r'[\\/]')) + 1);
        final candidates = <String>[
          dir + fileName,
          dir + 'sound/' + fileName,
          dir + 'Sound/' + fileName,
          dir + 'sound\\' + fileName,
          dir + 'Sound\\' + fileName,
          dir + 'res/' + fileName,
          dir + 'Res/' + fileName,
          dir + 'res\\' + fileName,
          dir + 'Res\\' + fileName,
          dir + 'media/' + fileName,
          dir + 'Media/' + fileName,
          dir + 'media\\' + fileName,
          dir + 'Media\\' + fileName,
          dir + 'audio/' + fileName,
          dir + 'Audio/' + fileName,
          dir + 'audio\\' + fileName,
          dir + 'Audio\\' + fileName,
        ];
        for (final p in candidates) {
          final f = File(p);
          if (await f.exists()) {
            return await f.readAsBytes();
          }
        }
        return null;
      }
    } catch (e) {
      // Silent failure, media may be packed in MDD
    }
    return null;
  }

  Future<List<String>> _resolveMddPathsFromMdx(String mdxPath) async {
    final paths = <String>[];
    try {
      final dir = mdxPath.substring(0, mdxPath.lastIndexOf(RegExp(r'[\\/]')) + 1);
      final base = mdxPath.substring(dir.length, mdxPath.length);
      final dot = base.lastIndexOf('.');
      final stem = dot >= 0 ? base.substring(0, dot) : base;
      final preferred = dir + stem + '.mdd';
      if (await File(preferred).exists()) {
        paths.add(preferred);
      }
      final d = Directory(dir);
      if (await d.exists()) {
        // search current directory
        await for (final entity in d.list()) {
          if (entity is File && entity.path.toLowerCase().endsWith('.mdd')) {
            if (!paths.contains(entity.path)) {
              paths.add(entity.path);
            }
          }
        }
        // search one-level subdirectories for .mdd
        await for (final sub in d.list()) {
          if (sub is Directory) {
            try {
              await for (final entity in sub.list()) {
                if (entity is File && entity.path.toLowerCase().endsWith('.mdd')) {
                  if (!paths.contains(entity.path)) {
                    paths.add(entity.path);
                  }
                }
              }
            } catch (_) {}
          }
        }
        // search two-level subdirectories and prefer matching stem
        final normalizedStem = stem.replaceAll(RegExp(r'\s+'), '').toLowerCase();
        Future<void> scanDeep(Directory baseDir, int depth) async {
          if (depth <= 0) return;
          try {
            await for (final ent in baseDir.list()) {
              if (ent is File) {
                final p = ent.path;
                if (p.toLowerCase().endsWith('.mdd')) {
                  final name = p.substring(p.lastIndexOf(RegExp(r'[\\/]')) + 1).replaceAll(' ', '').toLowerCase();
                  final prefer = name.contains(normalizedStem);
                  if (!paths.contains(p)) {
                    if (prefer) {
                      paths.insert(0, p);
                    } else {
                      paths.add(p);
                    }
                  }
                }
              } else if (ent is Directory) {
                await scanDeep(ent, depth - 1);
              }
            }
          } catch (_) {}
        }
        await scanDeep(d, 2);
      }
      if (paths.isNotEmpty) {
        print('[DictionaryQuery] mdd candidates: ${paths.join(' ; ')}');
      }
    } catch (_) {}
    return paths;
  }
  Future<Map<String, String>> _buildMddIndex(MddReader reader, String mddPath) async {
    final cached = _mddIndexCache[mddPath];
    if (cached != null) return cached;
    final map = <String, String>{};
    try {
      final keys = reader.keys();
      for (final k in keys) {
        final lower = k.toLowerCase();
        final idxSlash = lower.lastIndexOf('/');
        final idxBack = lower.lastIndexOf('\\');
        final idx = (idxSlash > idxBack ? idxSlash : idxBack) + 1;
        final base = lower.substring(idx);
        if (base.isNotEmpty && !map.containsKey(base)) {
          map[base] = k;
        }
      }
      _mddIndexCache[mddPath] = map;
      print('[DictionaryQuery] mdd index built: ${map.length}');
    } catch (e) {
      print('[DictionaryQuery] mdd index error: $e');
    }
    return map;
  }

  Future<void> _printMddRoot(MddReader reader, String mddPath, {int limit = 100}) async {
    try {
      final keys = reader.keys();
      final List<String> root = [];
      final Map<String, int> dirCount = {};
      for (final k in keys) {
        final n = k.replaceAll('\\', '/');
        if (!n.contains('/')) {
          root.add(k);
          continue;
        }
        final first = n.indexOf('/');
        final rest = n.substring(first + 1);
        if (first == 0 && !rest.contains('/')) {
          root.add(k);
        } else if (first >= 0) {
          final head = first == 0 ? (rest.contains('/') ? rest.substring(0, rest.indexOf('/')) : '') : n.substring(0, first);
          if (head.isNotEmpty) {
            dirCount[head] = (dirCount[head] ?? 0) + 1;
          }
        }
      }
      final dirs = dirCount.entries.map((e) => '/${e.key} (${e.value})').toList()..sort();
      _mddHeadsCache[mddPath] = dirCount.keys.toList();
      print('[DictionaryQuery] mdd index built: ${keys.length}');
      if (dirs.isNotEmpty) {
        print('[DictionaryQuery] mdd top-level dirs: ${dirs.join(' | ')} ; root=${root.length}');
      } else {
        print('[DictionaryQuery] mdd top-level dirs: (none) ; root=${root.length}');
      }
      if (root.isNotEmpty) {
        final sample = root.take(limit).map((e) {
          final s = e.replaceAll('\\', '/');
          return s.startsWith('/') ? s.substring(1) : s;
        }).toList();
        print('[DictionaryQuery] mdd root listing (${sample.length}): ${sample.join(' | ')}');
      }
    } catch (e) {
      print('[DictionaryQuery] mdd root listing error: $e');
    }
  }
  Future<List<String>> listMddRoot(Dictionary dictionary, {int limit = 100}) async {
    return [];
  }

  Future<Map<String, List<String>>> listMddRootAndDirs(Dictionary dictionary, {int limit = 100}) async {
    return {'root': [], 'dirs': []};
  }

  Future<List<String>> listMddDirChildren(Dictionary dictionary, String dir, {int limit = 200}) async {
    return [];
  }

  void dispose() {
    for (var reader in _readerCache.values) {
      reader.close();
    }
    _readerCache.clear();
  }
}