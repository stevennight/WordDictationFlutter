import 'package:dict_reader/dict_reader.dart';
import 'package:flutter_word_dictation/core/models/dictionary.dart';

class DictionaryQueryService {
  final Map<String, DictReader> _readerCache = {};
  final Map<String, List<RecordOffsetInfo>> _offsetCache = {};

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
        return await _resolveLink(reader, content, dictionaryPath: dictionary.path);
      }
      print('[DictionaryQuery] locate miss for "$word"');
    } catch (e) {
      _readerCache.remove(dictionary.path);
      print('[DictionaryQuery] error: $e');
    }
    return null;
  }

  Future<String?> _resolveLink(
    DictReader reader,
    String? content, {
    required String dictionaryPath,
    int depth = 0,
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
          return await _resolveLink(reader, data, dictionaryPath: dictionaryPath, depth: depth + 1);
        }
        final alt = numeric + 1;
        print('[DictionaryQuery] try alt index: $alt');
        final altInfo = await _getOffsetByIndex(reader, dictionaryPath, alt);
        if (altInfo != null) {
          final nextAlt = await reader.readOneMdx(altInfo);
          return await _resolveLink(reader, nextAlt, dictionaryPath: dictionaryPath, depth: depth + 1);
        }
        final altData = await _getDataByIndex(reader, dictionaryPath, alt);
        if (altData != null) {
          return await _resolveLink(reader, altData, dictionaryPath: dictionaryPath, depth: depth + 1);
        }
        return null;
      }
      final next = await reader.readOneMdx(info);
      return await _resolveLink(reader, next, dictionaryPath: dictionaryPath, depth: depth + 1);
    }

    final info = await reader.locate(target);
    if (info == null) return null;
    final next = await reader.readOneMdx(info);
    return await _resolveLink(reader, next, dictionaryPath: dictionaryPath, depth: depth + 1);
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

  void dispose() {
    for (var reader in _readerCache.values) {
      reader.close();
    }
    _readerCache.clear();
  }
}