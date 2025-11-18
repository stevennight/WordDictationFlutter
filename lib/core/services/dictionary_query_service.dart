import 'package:mdict_flutter/mdict_flutter.dart';
import 'package:flutter_word_dictation/core/models/dictionary.dart';
import 'dart:typed_data';
import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;

class DictionaryQueryService {
  final Map<String, MdictReader> _mdxCache = {};
  final Map<String, MdictReader> _mddCache = {};
  String? lastResolvedMediaKey;

  Future<MdictReader> _openMdx(String path) async {
    var r = _mdxCache[path];
    if (r != null) return r;
    r = MdictReader(path);
    await r.open();
    _mdxCache[path] = r;
    print('[DictionaryQuery] mdx opened: $path');
    return r;
  }

  Future<MdictReader> _openMdd(String path) async {
    var r = _mddCache[path];
    if (r != null) return r;
    r = MdictReader(path);
    await r.open();
    _mddCache[path] = r;
    print('[DictionaryQuery] mdd opened: $path');
    return r;
  }

  Future<String?> lookupWord(Dictionary dictionary, String key) async {
    try {
      final mdx = await _openMdx(dictionary.path);
      final def = await mdx.lookup(key);
      if (def == null || def.isEmpty) return null;
      return await _followLink(mdx, def, depth: 0);
    } catch (e) {
      _mdxCache.remove(dictionary.path);
      print('[DictionaryQuery] lookup error: $e');
      return null;
    }
  }



  Future<String?> _followLink(MdictReader mdx, String content, {int depth = 0}) async {
    if (!content.startsWith('@@@LINK=')) return _decodeIfBase64(content);
    if (depth > 16) return null;
    final target = content.substring(8).trim();
    final digits = _asDigits(target);
    if (digits != null) {
      final located = await mdx.locate(digits.toString());
      if (located == null || located.isEmpty) return null;
      return await _followLink(mdx, located, depth: depth + 1);
    }
    final next = await mdx.lookup(target);
    if (next == null || next.isEmpty) return null;
    return await _followLink(mdx, next, depth: depth + 1);
  }

  int? _asDigits(String raw) {
    final s = raw
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
    final d = s.replaceAll(RegExp(r'[^0-9]'), '');
    if (d.isEmpty) return null;
    return int.tryParse(d);
  }

  String _decodeIfBase64(String s) {
    final sn = s.trim();
    if (sn.isEmpty) return s;
    final re = RegExp(r'^[A-Za-z0-9+/=\r\n]+$');
    if (sn.length >= 16 && sn.length % 4 == 0 && re.hasMatch(sn) && !sn.contains('<') && !sn.contains('>')) {
      try {
        final bytes = base64Decode(sn);
        return const Utf8Decoder(allowMalformed: true).convert(bytes);
      } catch (_) {}
    }
    return s;
  }

  // dict_reader 顺序遍历相关方法移除；数值坐标解析交由 mdict-cpp 桥接

  Future<List<String>> searchKeys(Dictionary dictionary, String prefix, {int limit = 50}) async {
    try {
      final mdx = await _openMdx(dictionary.path);
      final list = await mdx.prefixSearch(prefix, limit: limit);
      print('[DictionaryQuery] prefixSearch("$prefix") -> ${list.length}');
      return list;
    } catch (e) {
      _mdxCache.remove(dictionary.path);
      print('[DictionaryQuery] search error: $e');
      return [];
    }
  }

  Future<Uint8List?> readMedia(Dictionary dictionary, String url) async {
    try {
      final lower = url.toLowerCase();
      if (lower.startsWith('http://') || lower.startsWith('https://')) {
        final resp = await http.get(Uri.parse(url));
        if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
          print('[DictionaryQuery] http media: ${resp.bodyBytes.length} bytes');
          return resp.bodyBytes;
        }
        return null;
      }
      if (lower.startsWith('mdd://') || lower.startsWith('res://') || lower.startsWith('sound://')) {
        final key = Uri.decodeComponent(url.split('://').last);
        final mddPaths = await _resolveMddPathsFromMdx(dictionary.path);
        for (final p in mddPaths) {
          try {
            final mdd = await _openMdd(p);
            var b64 = await mdd.locate(key, encodingOut: OutputEncoding.base64);
            var matchedKey = key;
            if ((b64 == null || b64.isEmpty) && !key.startsWith('/')) {
              b64 = await mdd.locate('/' + key, encodingOut: OutputEncoding.base64);
              matchedKey = '/' + key;
            }
            if (b64 == null || b64.isEmpty) {
              String? probeKey;
              for (var b = 0; b < mdd.keyBlockInfoList.length && b < 10; b++) {
                final list = mdd.decodeKeyBlockById(b);
                for (final k in list) {
                  final s = k.key.toLowerCase();
                  final idxSlash = s.lastIndexOf('/');
                  final idxBack = s.lastIndexOf('\\');
                  final idx = (idxSlash > idxBack ? idxSlash : idxBack) + 1;
                  final base = s.substring(idx);
                  if (base == key.toLowerCase()) { probeKey = k.key; break; }
                }
                if (probeKey != null) break;
              }
              if (probeKey != null) {
                matchedKey = probeKey;
                b64 = await mdd.locate(probeKey, encodingOut: OutputEncoding.base64);
              }
            }
            if (b64 != null && b64.isNotEmpty) {
              final bytes = base64Decode(b64);
              lastResolvedMediaKey = matchedKey;
              print('[DictionaryQuery] mdd media: ${bytes.length} bytes from $matchedKey');
              return Uint8List.fromList(bytes);
            }
          } catch (_) {}
        }
        return null;
      }
      return null;
    } catch (_) {
      return null;
    }
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
  

  void dispose() {
    for (var r in _mdxCache.values) {
      r.close();
    }
    for (var r in _mddCache.values) {
      r.close();
    }
    _mdxCache.clear();
    _mddCache.clear();
  }
}