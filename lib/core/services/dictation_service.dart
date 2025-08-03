import '../../shared/models/dictation_session.dart';
import '../../shared/models/dictation_result.dart';
import '../database/database_helper.dart';

class DictationService {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  /// Create a new dictation session
  Future<int> createSession(DictationSession session) async {
    final db = await _dbHelper.database;
    return await db.insert('dictation_sessions', session.toMap());
  }

  /// Get session by session ID
  Future<DictationSession?> getSession(String sessionId) async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'dictation_sessions',
      where: 'session_id = ?',
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

  /// Add word to session
  Future<int> addWordToSession(String sessionId, int wordId, int wordIndex) async {
    final db = await _dbHelper.database;
    return await db.insert('session_words', {
      'session_id': sessionId,
      'word_id': wordId,
      'word_order': wordIndex,
    });
  }

  /// Get session words
  Future<List<Map<String, dynamic>>> getSessionWords(String sessionId) async {
    final db = await _dbHelper.database;
    return await db.query(
      'session_words',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'word_order ASC',
    );
  }

  /// Save dictation result
  Future<int> saveResult(DictationResult result) async {
    final db = await _dbHelper.database;
    return await db.insert('dictation_results', result.toMap());
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

  /// Delete session and all related data
  Future<void> deleteSession(String sessionId) async {
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      await txn.delete(
        'dictation_results',
        where: 'session_id = ?',
        whereArgs: [sessionId],
      );
      await txn.delete(
        'session_words',
        where: 'session_id = ?',
        whereArgs: [sessionId],
      );
      await txn.delete(
        'dictation_sessions',
        where: 'session_id = ?',
        whereArgs: [sessionId],
      );
    });
  }

  /// Get all sessions
  Future<List<DictationSession>> getAllSessions() async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'dictation_sessions',
      orderBy: 'start_time DESC',
    );
    
    return List.generate(maps.length, (i) {
      return DictationSession.fromMap(maps[i]);
    });
  }

  /// Get sessions with pagination
  Future<List<DictationSession>> getSessionsPaginated({
    int limit = 20,
    int offset = 0,
  }) async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'dictation_sessions',
      orderBy: 'start_time DESC',
      limit: limit,
      offset: offset,
    );
    
    return List.generate(maps.length, (i) {
      return DictationSession.fromMap(maps[i]);
    });
  }

  /// Get session count
  Future<int> getSessionCount() async {
    final db = await _dbHelper.database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM dictation_sessions');
    return result.first['count'] as int;
  }

  /// Clear all data
  Future<void> clearAllData() async {
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      await txn.delete('dictation_results');
      await txn.delete('session_words');
      await txn.delete('dictation_sessions');
    });
  }
}