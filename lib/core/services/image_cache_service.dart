import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../../shared/utils/path_utils.dart';

/// 简单的内存图片缓存（LRU），用于避免历史记录列表切换过滤时重复读盘
class ImageCacheService {
  static final LinkedHashMap<String, Uint8List> _cache = LinkedHashMap();
  // 最大条目数，超过后按插入顺序淘汰旧条目
  static const int _maxEntries = 200;

  static Uint8List? get(String key) => _cache[key];

  static void set(String key, Uint8List bytes) {
    // 如果已存在，先删除以移动到队尾
    if (_cache.containsKey(key)) {
      _cache.remove(key);
    }
    _cache[key] = bytes;
    _evictIfNeeded();
  }

  static void _evictIfNeeded() {
    while (_cache.length > _maxEntries) {
      // 淘汰最早插入的条目
      final firstKey = _cache.keys.first;
      _cache.remove(firstKey);
    }
  }

  /// 异步从文件路径加载图片字节，并使用缓存
  static Future<Uint8List?> loadBytesForPath(String path) async {
    try {
      final absolutePath = await PathUtils.convertToAbsolutePath(path);
      final key = 'path:$absolutePath';
      final cached = get(key);
      if (cached != null) return cached;

      final file = File(absolutePath);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      set(key, bytes);
      return bytes;
    } catch (e) {
      debugPrint('读取图片字节失败: $e');
      return null;
    }
  }

  /// 手动清空缓存（可在内存压力大或退出页面时调用）
  static void clear() {
    _cache.clear();
  }
}