import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../models/dictation_session.dart';
import '../models/dictation_result.dart';
import '../../core/database/database_helper.dart';
import '../../core/services/config_service.dart';

class HistoryProvider with ChangeNotifier {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  ConfigService? _configService;
  
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
      
      // Load sessions (exclude inProgress status)
      final sessionMaps = await db.query(
        'dictation_sessions',
        where: 'status != ?',
        whereArgs: ['inProgress'],
        orderBy: 'start_time DESC',
      );
      
      _sessions = sessionMaps.map((map) => DictationSession.fromMap(map)).toList();
      
      // 检查并删除超出限制的最旧记录
      await _enforceHistoryLimit();
      
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

  /// Clear all inProgress sessions (called on app startup)
  Future<void> clearInProgressSessions() async {
    try {
      final db = await _dbHelper.database;
      
      // Delete all sessions with inProgress status
      await db.delete(
        'dictation_sessions',
        where: 'status = ?',
        whereArgs: ['inProgress'],
      );
      
      debugPrint('已清除所有inProgress状态的会话记录');
    } catch (e) {
      debugPrint('清除inProgress会话失败: $e');
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
        where: 'session_id = ?',
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
      
      // 先获取该会话的所有结果记录，以便删除关联的图片文件
      final resultMaps = await db.query(
        'dictation_results',
        where: 'session_id = ?',
        whereArgs: [sessionId],
      );
      
      // 收集需要删除的图片文件路径
      final imagesToDelete = <String>{};
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
          where: 'session_id = ?',
          whereArgs: [sessionId],
        );
      });
      
      // 删除关联的图片文件
      await _deleteImageFiles(imagesToDelete);
      
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
      
      // 先获取所有结果记录，以便删除关联的图片文件
      final resultMaps = await db.query('dictation_results');
      
      // 收集需要删除的图片文件路径
      final imagesToDelete = <String>{};
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
      
      await db.transaction((txn) async {
        await txn.delete('dictation_results');
        await txn.delete('session_words');
        await txn.delete('dictation_sessions');
      });
      
      // 删除关联的图片文件
      await _deleteImageFiles(imagesToDelete);
      
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
    
    // 按照实际完成数量计算整体准确率（总的正确数量/总的实际默写数量）
    final overallAccuracy = (totalCorrect + totalIncorrect) > 0
        ? (totalCorrect / (totalCorrect + totalIncorrect)) * 100
        : 0.0;

    return {
      'totalSessions': completedSessions.length,
      'totalWords': totalWords,
      'totalCorrect': totalCorrect,
      'totalIncorrect': totalIncorrect,
      'averageAccuracy': overallAccuracy,
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

  /// Get incorrect results for a specific session
  Future<List<DictationResult>> getIncorrectResultsForSession(String sessionId) async {
    try {
      final db = await _dbHelper.database;
      
      final maps = await db.query(
        'dictation_results',
        where: 'session_id = ? AND is_correct = 0',
        whereArgs: [sessionId],
        orderBy: 'word_index ASC',
      );
      
      return maps.map((map) => DictationResult.fromMap(map)).toList();
    } catch (e) {
      _setError('获取错题失败: $e');
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
  
  /// 删除图片文件
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

  /// Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }

  /// 检查并删除超出限制的最旧记录
  Future<void> _enforceHistoryLimit() async {
    _configService ??= await ConfigService.getInstance();
    final historyLimit = _configService!.getHistoryLimit();
    
    if (_sessions.length > historyLimit) {
      final db = await _dbHelper.database;
      
      // 获取需要删除的会话（最旧的记录）
      final sessionsToDelete = _sessions.skip(historyLimit).toList();
      
      for (final session in sessionsToDelete) {
        // 删除会话相关的结果记录
        await db.delete(
          'dictation_results',
          where: 'session_id = ?',
          whereArgs: [session.id],
        );
        
        // 删除会话记录
        await db.delete(
          'dictation_sessions',
          where: 'id = ?',
          whereArgs: [session.id],
        );
      }
      
      // 更新内存中的会话列表
      _sessions = _sessions.take(historyLimit).toList();
      
      debugPrint('已删除 ${sessionsToDelete.length} 条超出限制的历史记录');
    }
  }
}