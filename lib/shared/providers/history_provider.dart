import 'package:flutter/foundation.dart';

import '../models/dictation_session.dart';
import '../models/dictation_result.dart';
import '../../core/database/database_helper.dart';

class HistoryProvider with ChangeNotifier {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  
  List<DictationSession> _sessions = [];
  List<DictationResult> _results = [];
  bool _isLoading = false;
  String? _error;

  List<DictationSession> get sessions => _sessions;
  List<DictationResult> get results => _results;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Load all history sessions
  Future<void> loadHistory() async {
    _setLoading(true);
    _setError(null);

    try {
      final db = await _dbHelper.database;
      
      // Load sessions
      final sessionMaps = await db.query(
        'dictation_sessions',
        orderBy: 'start_time DESC',
      );
      
      _sessions = sessionMaps.map((map) => DictationSession.fromMap(map)).toList();
      
      // Load all results for statistics
      final resultMaps = await db.query('dictation_results');
      _results = resultMaps.map((map) => DictationResult.fromMap(map)).toList();
      
      notifyListeners();
    } catch (e) {
      _setError('加载历史记录失败: $e');
    } finally {
      _setLoading(false);
    }
  }

  /// Get session by ID
  Future<DictationSession?> getSessionById(int sessionId) async {
    try {
      final db = await _dbHelper.database;
      final maps = await db.query(
        'dictation_sessions',
        where: 'id = ?',
        whereArgs: [sessionId],
      );
      
      if (maps.isNotEmpty) {
        return DictationSession.fromMap(maps.first);
      }
      return null;
    } catch (e) {
      _setError('获取会话失败: $e');
      return null;
    }
  }
  
  /// Get session by session ID string
  Future<DictationSession?> getSession(String sessionId) async {
    try {
      final db = await _dbHelper.database;
      final maps = await db.query(
        'dictation_sessions',
        where: 'id = ?',
        whereArgs: [sessionId],
      );
      
      if (maps.isNotEmpty) {
        return DictationSession.fromMap(maps.first);
      }
      return null;
    } catch (e) {
      _setError('获取会话失败: $e');
      return null;
    }
  }

  /// Get results for a specific session
  Future<List<DictationResult>> getSessionResults(String sessionId) async {
    try {
      final db = await _dbHelper.database;
      final maps = await db.query(
        'dictation_results',
        where: 'session_id = ?',
        whereArgs: [sessionId],
        orderBy: 'word_index ASC',
      );
      
      return maps.map((map) => DictationResult.fromMap(map)).toList();
    } catch (e) {
      _setError('获取结果失败: $e');
      return [];
    }
  }

  /// Delete a session and its results
  Future<void> deleteSession(String sessionId) async {
    try {
      final db = await _dbHelper.database;
      
      await db.transaction((txn) async {
        // Delete results first
        await txn.delete(
          'dictation_results',
          where: 'session_id = ?',
          whereArgs: [sessionId],
        );
        
        // Delete session words
        await txn.delete(
          'session_words',
          where: 'session_id = ?',
          whereArgs: [sessionId],
        );
        
        // Delete session
        await txn.delete(
          'dictation_sessions',
          where: 'id = ?',
          whereArgs: [sessionId],
        );
      });
      
      // Remove from local list
      _sessions.removeWhere((session) => session.sessionId == sessionId);
      _results.removeWhere((result) => result.sessionId == sessionId);
      
      notifyListeners();
    } catch (e) {
      _setError('删除会话失败: $e');
    }
  }

  /// Clear all history
  Future<void> clearAllHistory() async {
    try {
      final db = await _dbHelper.database;
      
      await db.transaction((txn) async {
        await txn.delete('dictation_results');
        await txn.delete('session_words');
        await txn.delete('dictation_sessions');
      });
      
      _sessions.clear();
      _results.clear();
      
      notifyListeners();
    } catch (e) {
      _setError('清空历史记录失败: $e');
    }
  }

  /// Get statistics for all sessions
  Map<String, dynamic> getOverallStats() {
    if (_sessions.isEmpty) {
      return {
        'totalSessions': 0,
        'totalWords': 0,
        'totalCorrect': 0,
        'totalIncorrect': 0,
        'averageAccuracy': 0.0,
        'totalTime': Duration.zero,
      };
    }

    final completedSessions = _sessions.where((s) => s.isCompleted).toList();
    
    final totalWords = completedSessions.fold<int>(
      0, (sum, session) => sum + session.totalWords,
    );
    
    final totalCorrect = completedSessions.fold<int>(
      0, (sum, session) => sum + session.correctCount,
    );
    
    final totalIncorrect = completedSessions.fold<int>(
      0, (sum, session) => sum + session.incorrectCount,
    );
    
    final totalTime = completedSessions.fold<Duration>(
      Duration.zero,
      (sum, session) => sum + (session.duration ?? Duration.zero),
    );
    
    final averageAccuracy = completedSessions.isNotEmpty
        ? completedSessions.fold<double>(
            0.0, (sum, session) => sum + session.accuracy,
          ) / completedSessions.length
        : 0.0;

    return {
      'totalSessions': completedSessions.length,
      'totalWords': totalWords,
      'totalCorrect': totalCorrect,
      'totalIncorrect': totalIncorrect,
      'averageAccuracy': averageAccuracy,
      'totalTime': totalTime,
    };
  }

  /// Get recent sessions (last 7 days)
  List<DictationSession> getRecentSessions() {
    final sevenDaysAgo = DateTime.now().subtract(const Duration(days: 7));
    return _sessions
        .where((session) => session.startTime.isAfter(sevenDaysAgo))
        .toList();
  }

  /// Get sessions by date range
  List<DictationSession> getSessionsByDateRange(DateTime start, DateTime end) {
    return _sessions
        .where((session) => 
            session.startTime.isAfter(start) && 
            session.startTime.isBefore(end))
        .toList();
  }

  /// Get accuracy trend (last 10 sessions)
  List<double> getAccuracyTrend() {
    final completedSessions = _sessions
        .where((s) => s.isCompleted)
        .take(10)
        .toList();
    
    return completedSessions.map((s) => s.accuracy).toList();
  }

  /// Get most difficult words (most frequently incorrect)
  Future<List<Map<String, dynamic>>> getMostDifficultWords({int limit = 10}) async {
    try {
      final db = await _dbHelper.database;
      
      final maps = await db.rawQuery('''
        SELECT 
          prompt,
          answer,
          COUNT(*) as total_attempts,
          SUM(CASE WHEN is_correct = 0 THEN 1 ELSE 0 END) as incorrect_count,
          CAST(SUM(CASE WHEN is_correct = 0 THEN 1 ELSE 0 END) AS REAL) / COUNT(*) as error_rate
        FROM dictation_results 
        GROUP BY prompt, answer
        HAVING total_attempts >= 2
        ORDER BY error_rate DESC, total_attempts DESC
        LIMIT ?
      ''', [limit]);
      
      return maps;
    } catch (e) {
      _setError('获取难词统计失败: $e');
      return [];
    }
  }

  /// Export history data
  Future<Map<String, dynamic>> exportHistory() async {
    try {
      final allResults = <DictationResult>[];
      
      for (final session in _sessions) {
        final results = await getSessionResults(session.sessionId);
        allResults.addAll(results);
      }
      
      return {
        'sessions': _sessions.map((s) => s.toMap()).toList(),
        'results': allResults.map((r) => r.toMap()).toList(),
        'exportTime': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      _setError('导出数据失败: $e');
      return {};
    }
  }

  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void _setError(String? error) {
    _error = error;
    if (error != null) {
      notifyListeners();
    }
  }

  /// Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }
}