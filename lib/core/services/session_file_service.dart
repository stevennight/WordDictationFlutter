import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../shared/models/dictation_result.dart';
import '../../shared/models/dictation_session.dart';
import '../../shared/utils/path_utils.dart';

/// 会话文件服务
/// 将每次默写的手写图片打包到一个 `.session` 文件中，
/// 并提供读取该文件中图片的方法，以简化同步逻辑。
class SessionFileService {
  static const String _sessionsDirName = 'userdata/sessions';

  /// 获取会话文件的本地绝对路径
  static Future<String> getSessionFilePath(String sessionId) async {
    final appDir = await PathUtils.getAppDirectory();
    final dir = Directory(p.join(appDir.path, _sessionsDirName));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return p.join(dir.path, '$sessionId.session');
  }

  /// 将会话相关的图片打包存储到 `.session` 文件
  static Future<File> saveSessionFile(
    DictationSession session,
    List<DictationResult> results,
  ) async {
    final filePath = await getSessionFilePath(session.sessionId);

    final Map<String, dynamic> payload = {
      'version': 1,
      'sessionId': session.sessionId,
      'createdAt': DateTime.now().toIso8601String(),
      'images': <String, Map<String, String?>>{}, // wordIndex -> {original, annotated}
    };

    for (final r in results) {
      String? originalBase64;
      String? annotatedBase64;

      if (r.originalImagePath != null && r.originalImagePath!.isNotEmpty) {
        try {
          final abs = await PathUtils.convertToAbsolutePath(r.originalImagePath!);
          final f = File(abs);
          if (await f.exists()) {
            final bytes = await f.readAsBytes();
            originalBase64 = base64Encode(bytes);
          }
        } catch (e) {
          debugPrint('读取原始手写图片失败: $e');
        }
      }

      if (r.annotatedImagePath != null && r.annotatedImagePath!.isNotEmpty) {
        try {
          final abs = await PathUtils.convertToAbsolutePath(r.annotatedImagePath!);
          final f = File(abs);
          if (await f.exists()) {
            final bytes = await f.readAsBytes();
            annotatedBase64 = base64Encode(bytes);
          }
        } catch (e) {
          debugPrint('读取批注图片失败: $e');
        }
      }

      // 仅在有任一图片时写入
      if (originalBase64 != null || annotatedBase64 != null) {
        payload['images'][r.wordIndex.toString()] = {
          'original': originalBase64,
          'annotated': annotatedBase64,
        };
      }
    }

    final file = File(filePath);
    await file.writeAsString(jsonEncode(payload));
    return file;
  }

  /// 从 `.session` 文件读取指定单词索引的图片字节
  static Future<Uint8List?> loadImageBytes(
    String sessionId,
    int wordIndex, {
    bool annotated = false,
  }) async {
    try {
      final filePath = await getSessionFilePath(sessionId);
      final file = File(filePath);
      if (!await file.exists()) return null;

      final content = await file.readAsString();
      final Map<String, dynamic> data = jsonDecode(content);
      final Map<String, dynamic>? images =
          (data['images'] as Map<String, dynamic>?);
      if (images == null) return null;

      final Map<String, dynamic>? entry =
          images[wordIndex.toString()] as Map<String, dynamic>?;
      if (entry == null) return null;

      final String? b64 = annotated
          ? entry['annotated'] as String?
          : entry['original'] as String?;
      if (b64 == null || b64.isEmpty) return null;

      return Uint8List.fromList(base64Decode(b64));
    } catch (e) {
      debugPrint('读取session图片失败: $e');
      return null;
    }
  }
}