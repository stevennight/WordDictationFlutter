import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../database/database_helper.dart';
import '../../shared/models/dictation_session.dart';

/// 历史记录删除服务
/// 统一处理所有历史记录删除操作，包括：
/// 1. 用户手动删除
/// 2. 超过存储上限的自动删除
/// 3. 同步操作中的删除
class HistoryDeletionService {
  static final HistoryDeletionService _instance = HistoryDeletionService._internal();
  factory HistoryDeletionService() => _instance;
  static HistoryDeletionService get instance => _instance;
  HistoryDeletionService._internal();

  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  /// 软删除单个会话（用户手动删除）
  /// [sessionId] 会话ID
  /// [deleteImages] 是否删除关联的图片文件，默认为true
  Future<void> softDeleteSession(String sessionId, {bool deleteImages = true}) async {
    try {
      final db = await _dbHelper.database;
      
      // 收集需要删除的图片文件路径
      Set<String> imagesToDelete = {};
      if (deleteImages) {
        imagesToDelete = await _collectSessionImagePaths(sessionId);
      }
      
      // 软删除会话（标记为已删除）
      await db.update(
        'dictation_sessions',
        {
          'deleted': 1,
          'deleted_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'session_id = ?',
        whereArgs: [sessionId],
      );
      
      // 删除关联的图片文件
      if (deleteImages && imagesToDelete.isNotEmpty) {
        await _deleteImageFiles(imagesToDelete);
      }
      
      debugPrint('已软删除会话: $sessionId');
    } catch (e) {
      debugPrint('软删除会话失败: $sessionId, $e');
      rethrow;
    }
  }

  /// 硬删除单个会话（物理删除数据库记录）
  /// [sessionId] 会话ID
  /// [deleteImages] 是否删除关联的图片文件，默认为true
  /// [deleteSession] 是否删除会话记录本身，默认为true
  Future<void> hardDeleteSession(String sessionId, {bool deleteImages = true, bool deleteSession = true}) async {
    try {
      final db = await _dbHelper.database;
      
      // 收集需要删除的图片文件路径
      Set<String> imagesToDelete = {};
      if (deleteImages) {
        imagesToDelete = await _collectSessionImagePaths(sessionId);
      }
      
      await db.transaction((txn) async {
        // 删除会话相关的结果记录
        await txn.delete(
          'dictation_results',
          where: 'session_id = ?',
          whereArgs: [sessionId],
        );
        
        // 删除会话相关的单词关联记录
        await txn.delete(
          'session_words',
          where: 'session_id = ?',
          whereArgs: [sessionId],
        );
        
        // 删除会话记录（可选）
        if (deleteSession) {
          await txn.delete(
            'dictation_sessions',
            where: 'session_id = ?',
            whereArgs: [sessionId],
          );
        }
      });
      
      // 删除关联的图片文件
      if (deleteImages && imagesToDelete.isNotEmpty) {
        await _deleteImageFiles(imagesToDelete);
      }
      
      debugPrint('已硬删除会话${deleteSession ? '' : '结果和关联'}: $sessionId');
    } catch (e) {
      debugPrint('硬删除会话${deleteSession ? '' : '结果和关联'}失败: $sessionId, $e');
      rethrow;
    }
  }

  /// 删除会话的结果和单词关联记录（不删除会话本身）
  /// [sessionId] 会话ID
  /// [deleteImages] 是否删除关联的图片文件，默认为true
  Future<void> deleteSessionResults(String sessionId, {bool deleteImages = true}) async {
    await hardDeleteSession(sessionId, deleteImages: deleteImages, deleteSession: false);
  }

  /// 批量软删除会话
  /// [sessionIds] 会话ID列表
  /// [deleteImages] 是否删除关联的图片文件，默认为true
  Future<void> batchSoftDeleteSessions(List<String> sessionIds, {bool deleteImages = true}) async {
    if (sessionIds.isEmpty) return;
    
    try {
      final db = await _dbHelper.database;
      
      // 收集需要删除的图片文件路径
      Set<String> imagesToDelete = {};
      if (deleteImages) {
        for (final sessionId in sessionIds) {
          final sessionImages = await _collectSessionImagePaths(sessionId);
          imagesToDelete.addAll(sessionImages);
        }
      }
      
      // 批量软删除会话
      final placeholders = sessionIds.map((_) => '?').join(',');
      await db.update(
        'dictation_sessions',
        {
          'deleted': 1,
          'deleted_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'session_id IN ($placeholders)',
        whereArgs: sessionIds,
      );
      
      // 删除关联的图片文件
      if (deleteImages && imagesToDelete.isNotEmpty) {
        await _deleteImageFiles(imagesToDelete);
      }
      
      debugPrint('已批量软删除 ${sessionIds.length} 个会话');
    } catch (e) {
      debugPrint('批量软删除会话失败: $e');
      rethrow;
    }
  }

  /// 批量硬删除会话
  /// [sessionIds] 会话ID列表
  /// [deleteImages] 是否删除关联的图片文件，默认为true
  Future<void> batchHardDeleteSessions(List<String> sessionIds, {bool deleteImages = true}) async {
    if (sessionIds.isEmpty) return;
    
    try {
      final db = await _dbHelper.database;
      
      // 收集需要删除的图片文件路径
      Set<String> imagesToDelete = {};
      if (deleteImages) {
        for (final sessionId in sessionIds) {
          final sessionImages = await _collectSessionImagePaths(sessionId);
          imagesToDelete.addAll(sessionImages);
        }
      }
      
      await db.transaction((txn) async {
        final placeholders = sessionIds.map((_) => '?').join(',');
        
        // 删除会话相关的结果记录
        await txn.delete(
          'dictation_results',
          where: 'session_id IN ($placeholders)',
          whereArgs: sessionIds,
        );
        
        // 删除会话相关的单词关联记录
        await txn.delete(
          'session_words',
          where: 'session_id IN ($placeholders)',
          whereArgs: sessionIds,
        );
        
        // 删除会话记录
        await txn.delete(
          'dictation_sessions',
          where: 'session_id IN ($placeholders)',
          whereArgs: sessionIds,
        );
      });
      
      // 删除关联的图片文件
      if (deleteImages && imagesToDelete.isNotEmpty) {
        await _deleteImageFiles(imagesToDelete);
      }
      
      debugPrint('已批量硬删除 ${sessionIds.length} 个会话');
    } catch (e) {
      debugPrint('批量硬删除会话失败: $e');
      rethrow;
    }
  }

  /// 清空所有历史记录（硬删除）
  /// [deleteImages] 是否删除关联的图片文件，默认为true
  Future<void> clearAllHistory({bool deleteImages = true}) async {
    try {
      final db = await _dbHelper.database;
      
      // 收集需要删除的图片文件路径
      Set<String> imagesToDelete = {};
      if (deleteImages) {
        imagesToDelete = await _collectAllImagePaths();
      }
      
      await db.transaction((txn) async {
        await txn.delete('dictation_results');
        await txn.delete('session_words');
        await txn.delete('dictation_sessions');
      });
      
      // 删除关联的图片文件
      if (deleteImages && imagesToDelete.isNotEmpty) {
        await _deleteImageFiles(imagesToDelete);
      }
      
      debugPrint('已清空所有历史记录');
    } catch (e) {
      debugPrint('清空历史记录失败: $e');
      rethrow;
    }
  }

  /// 删除超出存储限制的最旧记录（硬删除）
  /// [sessions] 当前会话列表（按时间倒序排列）
  /// [limit] 存储限制数量
  /// [deleteImages] 是否删除关联的图片文件，默认为true
  Future<void> enforceHistoryLimit(List<DictationSession> sessions, int limit, {bool deleteImages = true}) async {
    if (sessions.length <= limit) return;
    
    try {
      final db = await _dbHelper.database;
      
      // 获取需要删除的会话（最旧的记录）
      final sessionsToDelete = sessions.skip(limit).toList();
      final sessionIdsToDelete = sessionsToDelete.map((s) => s.sessionId).toList();
      
      // 收集需要删除的图片文件路径
      Set<String> imagesToDelete = {};
      if (deleteImages) {
        for (final sessionId in sessionIdsToDelete) {
          final sessionImages = await _collectSessionImagePaths(sessionId);
          imagesToDelete.addAll(sessionImages);
        }
      }
      
      await db.transaction((txn) async {
        for (final session in sessionsToDelete) {
          // 删除会话相关的结果记录
          await txn.delete(
            'dictation_results',
            where: 'session_id = ?',
            whereArgs: [session.sessionId],
          );
          
          // 删除会话相关的单词关联记录
          await txn.delete(
            'session_words',
            where: 'session_id = ?',
            whereArgs: [session.sessionId],
          );
          
          // 删除会话记录（使用数据库ID）
          await txn.delete(
            'dictation_sessions',
            where: 'id = ?',
            whereArgs: [session.id],
          );
        }
      });
      
      // 删除关联的图片文件
      if (deleteImages && imagesToDelete.isNotEmpty) {
        await _deleteImageFiles(imagesToDelete);
      }
      
      debugPrint('已删除 ${sessionsToDelete.length} 条超出限制的历史记录');
    } catch (e) {
      debugPrint('删除超出限制的历史记录失败: $e');
      rethrow;
    }
  }

  /// 清除所有进行中的会话（硬删除）
  /// 通常在应用启动时调用
  Future<void> clearInProgressSessions() async {
    try {
      final db = await _dbHelper.database;
      
      // 删除所有进行中状态的会话
      await db.delete(
        'dictation_sessions',
        where: 'status = ?',
        whereArgs: ['inProgress'],
      );
      
      debugPrint('已清除所有inProgress状态的会话记录');
    } catch (e) {
      debugPrint('清除inProgress会话失败: $e');
      rethrow;
    }
  }

  /// 软删除本地存在但远端不存在的记录（用于同步）
  /// [remoteSessionIds] 远端会话ID集合
  /// [deleteImages] 是否删除关联的图片文件，默认为true
  Future<void> deleteLocalOnlyRecords(Set<String> remoteSessionIds, {bool deleteImages = true}) async {
    try {
      debugPrint('[HistoryDeletion] 开始检查并软删除本地多余的记录');
      
      debugPrint('[HistoryDeletion] 远端会话数量: ${remoteSessionIds.length}');
      
      // 获取本地所有未删除的会话
      final db = await _dbHelper.database;
      final localSessionMaps = await db.query(
        'dictation_sessions',
        columns: ['session_id'],
        where: "status != 'inProgress' AND (deleted IS NULL OR deleted = 0)", // 排除进行中的会话和已删除的会话
      );
      
      final localSessionIds = localSessionMaps.map((m) => m['session_id'] as String).toSet();
      debugPrint('[HistoryDeletion] 本地未删除会话数量: ${localSessionIds.length}');
      
      // 找出本地存在但远端不存在的会话ID
      final sessionsToSoftDelete = localSessionIds.difference(remoteSessionIds);
      debugPrint('[HistoryDeletion] 需要软删除的本地会话数量: ${sessionsToSoftDelete.length}');
      
      if (sessionsToSoftDelete.isEmpty) {
        debugPrint('[HistoryDeletion] 没有需要软删除的本地记录');
        return;
      }
      
      // 批量软删除会话
      await batchSoftDeleteSessions(sessionsToSoftDelete.toList(), deleteImages: deleteImages);
      
      debugPrint('[HistoryDeletion] 成功软删除 ${sessionsToSoftDelete.length} 个本地多余的会话记录');
    } catch (e) {
      debugPrint('[HistoryDeletion] 软删除本地多余记录时出错: $e');
      // 不抛出异常，避免影响整个同步过程
    }
  }

  /// 收集单个会话的所有图片文件路径
  /// [sessionId] 会话ID
  /// 返回该会话关联的所有图片文件路径集合
  Future<Set<String>> _collectSessionImagePaths(String sessionId) async {
    final db = await _dbHelper.database;
    final imagesToDelete = <String>{};
    
    // 获取该会话的所有结果记录
    final resultMaps = await db.query(
      'dictation_results',
      where: 'session_id = ?',
      whereArgs: [sessionId],
    );
    
    for (final resultMap in resultMaps) {
      final originalPath = resultMap['original_image_path'] as String?;
      final annotatedPath = resultMap['annotated_image_path'] as String?;
      
      if (originalPath != null && originalPath.isNotEmpty) {
        imagesToDelete.add(originalPath);
      }
      if (annotatedPath != null && annotatedPath.isNotEmpty) {
        imagesToDelete.add(annotatedPath);
      }
    }
    
    return imagesToDelete;
  }

  /// 收集所有历史记录的图片文件路径
  /// 返回所有历史记录关联的图片文件路径集合
  Future<Set<String>> _collectAllImagePaths() async {
    final db = await _dbHelper.database;
    final imagesToDelete = <String>{};
    
    // 获取所有结果记录
    final resultMaps = await db.query('dictation_results');
    
    for (final resultMap in resultMaps) {
      final originalPath = resultMap['original_image_path'] as String?;
      final annotatedPath = resultMap['annotated_image_path'] as String?;
      
      if (originalPath != null && originalPath.isNotEmpty) {
        imagesToDelete.add(originalPath);
      }
      if (annotatedPath != null && annotatedPath.isNotEmpty) {
        imagesToDelete.add(annotatedPath);
      }
    }
    
    return imagesToDelete;
  }

  /// 删除图片文件
  /// [imagePaths] 图片文件路径集合
  Future<void> _deleteImageFiles(Set<String> imagePaths) async {
    for (final imagePath in imagePaths) {
      try {
        File imageFile;
        
        // 如果是绝对路径，直接使用
        if (path.isAbsolute(imagePath)) {
          imageFile = File(imagePath);
        } else {
          // 如果是相对路径，转换为绝对路径
          String appDir;
          if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
            // Get executable directory for desktop platforms
            final executablePath = Platform.resolvedExecutable;
            appDir = path.dirname(executablePath);
          } else {
            // Fallback to documents directory for mobile platforms
            final appDocDir = await getApplicationDocumentsDirectory();
            appDir = appDocDir.path;
          }
          
          final absolutePath = path.join(appDir, imagePath);
          imageFile = File(absolutePath);
        }
        
        if (await imageFile.exists()) {
          await imageFile.delete();
          debugPrint('已删除图片文件: $imagePath');
        } else {
          debugPrint('图片文件不存在，跳过删除: $imagePath');
        }
      } catch (e) {
        debugPrint('删除图片文件失败: $imagePath, $e');
      }
    }
  }
}