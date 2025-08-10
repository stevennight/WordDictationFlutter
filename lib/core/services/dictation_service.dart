import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../../shared/models/dictation_session.dart';
import '../../shared/models/dictation_result.dart';
import '../database/database_helper.dart';
import 'history_deletion_service.dart';

class DictationService {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final HistoryDeletionService _deletionService = HistoryDeletionService.instance;

  /// Create a new dictation session
  Future<int> createSession(DictationSession session) async {
    final db = await _dbHelper.database;
    try {
      return await db.insert('dictation_sessions', session.toMap());
    } catch (e) {
      // 如果出现UNIQUE约束冲突，使用INSERT OR REPLACE
      if (e.toString().contains('UNIQUE constraint failed')) {
        return await db.insert(
          'dictation_sessions', 
          session.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      rethrow;
    }
  }

  /// Get session by session ID
  Future<DictationSession?> getSession(String sessionId) async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'dictation_sessions',
      where: 'session_id = ? AND deleted = 0',
      whereArgs: [sessionId],
    );
    
    if (maps.isNotEmpty) {
      return DictationSession.fromMap(maps.first);
    }
    return null;
  }

  /// Update session
  Future<int> updateSession(DictationSession session) async {
    final db = await _dbHelper.database;
    return await db.update(
      'dictation_sessions',
      session.toMap(),
      where: 'session_id = ?',
      whereArgs: [session.sessionId],
    );
  }

  // Note: session_words related methods removed as table is no longer needed

  /// Save dictation result
  Future<int> saveResult(DictationResult result) async {
    final db = await _dbHelper.database;
    
    // 调试信息：检查传入的MD5值
    debugPrint('DictationService.saveResult: wordIndex=${result.wordIndex}, originalMd5=${result.originalImageMd5}, annotatedMd5=${result.annotatedImageMd5}');
    
    try {
      // 先检查是否已存在相同的记录（基于session_id和word_index）
      final existing = await db.query(
        'dictation_results',
        where: 'session_id = ? AND word_index = ?',
        whereArgs: [result.sessionId, result.wordIndex],
      );
      
      if (existing.isNotEmpty) {
        // 如果已存在，更新记录而不是插入新记录
        final existingId = existing.first['id'] as int;
        final updatedResult = result.copyWith(id: existingId);
        final resultMap = updatedResult.toMap();
        debugPrint('更新数据库记录: id=$existingId, originalMd5=${resultMap['original_image_md5']}, annotatedMd5=${resultMap['annotated_image_md5']}');
        await db.update(
          'dictation_results',
          resultMap,
          where: 'id = ?',
          whereArgs: [existingId],
        );
        return existingId;
      } else {
        // 如果不存在，插入新记录
        final resultMap = result.toMap();
        return await db.insert('dictation_results', resultMap);
      }
    } catch (e) {
      // 如果仍然出现唯一性冲突，使用INSERT OR REPLACE
      return await db.insert(
        'dictation_results', 
        result.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  /// Get results for a session
  Future<List<DictationResult>> getSessionResults(String sessionId) async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'dictation_results',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'word_index ASC',
    );
    
    return List.generate(maps.length, (i) {
      return DictationResult.fromMap(maps[i]);
    });
  }

  /// Update result
  Future<int> updateResult(DictationResult result) async {
    final db = await _dbHelper.database;
    return await db.update(
      'dictation_results',
      result.toMap(),
      where: 'id = ?',
      whereArgs: [result.id],
    );
  }

  /// Soft delete session (mark as deleted)
  Future<void> deleteSession(String sessionId) async {
    final db = await _dbHelper.database;
    await db.update(
      'dictation_sessions',
      {
        'deleted': 1,
        'deleted_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'session_id = ?',
      whereArgs: [sessionId],
    );
  }

  /// Hard delete session and all related data (for cleanup)
  Future<void> hardDeleteSession(String sessionId) async {
    await _deletionService.hardDeleteSession(sessionId);
  }

  /// Get all sessions (excluding deleted)
  Future<List<DictationSession>> getAllSessions() async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'dictation_sessions',
      where: 'deleted = 0',
      orderBy: 'start_time DESC',
    );
    
    return List.generate(maps.length, (i) {
      return DictationSession.fromMap(maps[i]);
    });
  }

  /// Get all sessions including deleted (for sync purposes)
  Future<List<DictationSession>> getAllSessionsIncludingDeleted() async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'dictation_sessions',
      orderBy: 'start_time DESC',
    );
    
    return List.generate(maps.length, (i) {
      return DictationSession.fromMap(maps[i]);
    });
  }

  /// Get sessions with pagination (excluding deleted)
  Future<List<DictationSession>> getSessionsPaginated({
    int limit = 20,
    int offset = 0,
  }) async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'dictation_sessions',
      where: 'deleted = 0',
      orderBy: 'start_time DESC',
      limit: limit,
      offset: offset,
    );
    
    return List.generate(maps.length, (i) {
      return DictationSession.fromMap(maps[i]);
    });
  }

  /// Get session count (excluding deleted)
  Future<int> getSessionCount() async {
    final db = await _dbHelper.database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM dictation_sessions WHERE deleted = 0');
    return result.first['count'] as int;
  }

  /// Clear all data
  Future<void> clearAllData() async {
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      await txn.delete('dictation_results');
      await txn.delete('dictation_sessions');
    });
  }
}