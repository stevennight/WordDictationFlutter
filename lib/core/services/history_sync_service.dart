import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../shared/models/dictation_session.dart';
import '../../shared/models/dictation_result.dart';
import '../database/database_helper.dart';
import 'sync_service.dart';
import 'dictation_service.dart';
import 'image_sync_manager.dart';

/// 历史记录同步数据结构
class HistorySyncData {
  final String version;
  final String dataType;
  final String deviceId;
  final DateTime lastModified;
  final List<SessionSyncData> sessions;

  HistorySyncData({
    required this.version,
    required this.dataType,
    required this.deviceId,
    required this.lastModified,
    required this.sessions,
  });

  Map<String, dynamic> toMap() {
    return {
      'version': version,
      'dataType': dataType,
      'deviceId': deviceId,
      'lastModified': lastModified.toIso8601String(),
      'sessions': sessions.map((s) => s.toMap()).toList(),
    };
  }

  factory HistorySyncData.fromMap(Map<String, dynamic> map) {
    return HistorySyncData(
      version: map['version'] ?? '1.0.0',
      dataType: map['dataType'] ?? 'history',
      deviceId: map['deviceId'] ?? '',
      lastModified: DateTime.parse(map['lastModified']),
      sessions: (map['sessions'] as List<dynamic>)
          .map((s) => SessionSyncData.fromMap(s))
          .toList(),
    );
  }
}

/// 单个会话同步数据
class SessionSyncData {
  final String sessionId;
  final DateTime lastModified;
  final Map<String, dynamic> sessionData;
  final List<Map<String, dynamic>> results;
  final List<ImageFileInfo> imageFiles;

  SessionSyncData({
    required this.sessionId,
    required this.lastModified,
    required this.sessionData,
    required this.results,
    required this.imageFiles,
  });

  Map<String, dynamic> toMap() {
    return {
      'sessionId': sessionId,
      'lastModified': lastModified.toIso8601String(),
      'sessionData': sessionData,
      'results': results,
      'imageFiles': imageFiles.map((f) => f.toMap()).toList(),
    };
  }

  factory SessionSyncData.fromMap(Map<String, dynamic> map) {
    return SessionSyncData(
      sessionId: map['sessionId'],
      lastModified: DateTime.parse(map['lastModified']),
      sessionData: Map<String, dynamic>.from(map['sessionData']),
      results: List<Map<String, dynamic>>.from(map['results']),
      imageFiles: (map['imageFiles'] as List<dynamic>)
          .map((f) => ImageFileInfo.fromMap(f))
          .toList(),
    );
  }
}

/// 图片文件信息
class ImageFileInfo {
  final String relativePath;
  final String hash;
  final int size;
  final DateTime lastModified;

  ImageFileInfo({
    required this.relativePath,
    required this.hash,
    required this.size,
    required this.lastModified,
  });

  Map<String, dynamic> toMap() {
    return {
      'relativePath': relativePath,
      'hash': hash,
      'size': size,
      'lastModified': lastModified.toIso8601String(),
    };
  }

  factory ImageFileInfo.fromMap(Map<String, dynamic> map) {
    return ImageFileInfo(
      relativePath: map['relativePath'],
      hash: map['hash'],
      size: map['size'],
      lastModified: DateTime.parse(map['lastModified']),
    );
  }
}

/// 历史记录同步服务
class HistorySyncService {
  static final HistorySyncService _instance = HistorySyncService._internal();
  factory HistorySyncService() => _instance;
  HistorySyncService._internal();

  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final DictationService _dictationService = DictationService();
  late ImageSyncManager _imageSyncManager;
  late String _deviceId;
  late Directory _appDocDir;

  /// 初始化服务
  Future<void> initialize() async {
    _appDocDir = await getApplicationDocumentsDirectory();
    _deviceId = await _getOrCreateDeviceId();
    _imageSyncManager = ImageSyncManager();
    await _imageSyncManager.initialize();
  }

  /// 获取或创建设备ID
  Future<String> _getOrCreateDeviceId() async {
    final file = File(path.join(_appDocDir.path, 'device_id.txt'));
    if (await file.exists()) {
      return await file.readAsString();
    } else {
      final deviceId = DateTime.now().millisecondsSinceEpoch.toString();
      await file.writeAsString(deviceId);
      return deviceId;
    }
  }

  /// 导出历史记录数据（用于上传）
  Future<Map<String, dynamic>> exportHistoryData({DateTime? since}) async {
    final db = await _dbHelper.database;
    
    // 查询会话数据
    String whereClause = "status != 'inProgress'";
    List<dynamic> whereArgs = [];
    
    if (since != null) {
      whereClause += " AND start_time > ?";
      whereArgs.add(since.millisecondsSinceEpoch);
    }
    
    final sessionMaps = await db.query(
      'dictation_sessions',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'start_time DESC',
    );

    final List<SessionSyncData> sessions = [];
    
    for (final sessionMap in sessionMaps) {
      final sessionId = sessionMap['session_id'] as String;
      
      // 获取会话结果
      final resultMaps = await db.query(
        'dictation_results',
        where: 'session_id = ?',
        whereArgs: [sessionId],
        orderBy: 'word_index ASC',
      );
      
      // 收集所有图片文件信息
      final Set<String> allImagePaths = {};
      for (final resultMap in resultMaps) {
        final originalPath = resultMap['original_image_path'] as String?;
        final annotatedPath = resultMap['annotated_image_path'] as String?;
        
        if (originalPath != null && originalPath.isNotEmpty) {
          allImagePaths.add(originalPath);
        }
        if (annotatedPath != null && annotatedPath.isNotEmpty) {
          allImagePaths.add(annotatedPath);
        }
      }

      final List<ImageFileInfo> imageFiles = [];
      for (final imagePath in allImagePaths) {
        final imageInfo = await _imageSyncManager.getImageFileInfo(imagePath);
        if (imageInfo != null) {
          imageFiles.add(imageInfo);
        }
      }
      
      sessions.add(SessionSyncData(
        sessionId: sessionId,
        lastModified: DateTime.fromMillisecondsSinceEpoch(
          sessionMap['start_time'] as int,
        ),
        sessionData: Map<String, dynamic>.from(sessionMap),
        results: resultMaps.map((r) => Map<String, dynamic>.from(r)).toList(),
        imageFiles: imageFiles,
      ));
    }

    final syncData = HistorySyncData(
      version: '1.0.0',
      dataType: 'history',
      deviceId: _deviceId,
      lastModified: DateTime.now(),
      sessions: sessions,
    );

    return syncData.toMap();
  }



  /// 导入历史记录数据（用于下载）
  Future<SyncResult> importHistoryData(Map<String, dynamic> data) async {
    try {
      final syncData = HistorySyncData.fromMap(data);
      
      // 检测冲突
      final conflicts = await _detectConflicts(syncData);
      if (conflicts.isNotEmpty) {
        return SyncResult.failure('检测到冲突: ${conflicts.join(", ")}');
      }
      
      // 导入会话数据
      int importedSessions = 0;
      int importedResults = 0;
      
      for (final sessionSync in syncData.sessions) {
        // 检查会话是否已存在
        final existingSession = await _dictationService.getSession(sessionSync.sessionId);
        
        if (existingSession == null) {
          // 创建新会话
          final session = DictationSession.fromMap(sessionSync.sessionData);
          await _dictationService.createSession(session);
          importedSessions++;
          
          // 导入结果
          for (final resultData in sessionSync.results) {
            final result = DictationResult.fromMap(resultData);
            await _dictationService.saveResult(result);
            importedResults++;
          }
        } else {
          // 检查是否需要更新
          final existingModified = existingSession.startTime;
          if (sessionSync.lastModified.isAfter(existingModified)) {
            // 更新会话
            final session = DictationSession.fromMap(sessionSync.sessionData);
            await _dictationService.updateSession(session);
            
            // 更新结果（简单起见，删除旧结果后重新插入）
            await _deleteSessionResults(sessionSync.sessionId);
            for (final resultData in sessionSync.results) {
              final result = DictationResult.fromMap(resultData);
              await _dictationService.saveResult(result);
              importedResults++;
            }
          }
        }
      }
      
      return SyncResult.success(
        message: '成功导入 $importedSessions 个会话，$importedResults 个结果',
        data: {
          'importedSessions': importedSessions,
          'importedResults': importedResults,
        },
      );
    } catch (e) {
      return SyncResult.failure('导入历史记录失败: $e');
    }
  }

  /// 检测同步冲突
  Future<List<String>> _detectConflicts(HistorySyncData syncData) async {
    final List<String> conflicts = [];
    
    // 检查设备ID冲突（同一设备不应该产生冲突）
    if (syncData.deviceId == _deviceId) {
      // 同一设备，跳过冲突检测
      return conflicts;
    }
    
    // 检查会话冲突
    for (final sessionSync in syncData.sessions) {
      final existingSession = await _dictationService.getSession(sessionSync.sessionId);
      if (existingSession != null) {
        final existingModified = existingSession.startTime;
        final remoteModified = sessionSync.lastModified;
        
        // 如果两个时间戳相差很小（比如1秒内），认为是同一次修改
        final timeDiff = existingModified.difference(remoteModified).abs();
        if (timeDiff.inSeconds > 1) {
          conflicts.add('会话 ${sessionSync.sessionId} 存在冲突');
        }
      }
    }
    
    return conflicts;
  }

  /// 删除会话结果
  Future<void> _deleteSessionResults(String sessionId) async {
    final db = await _dbHelper.database;
    await db.delete(
      'dictation_results',
      where: 'session_id = ?',
      whereArgs: [sessionId],
    );
  }

  /// 计算文件哈希值
  Future<String> calculateFileHash(File file) async {
    final bytes = await file.readAsBytes();
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// 检查文件是否需要上传
  Future<bool> needsUpload(String filePath, String? remoteHash) async {
    if (remoteHash == null) return true;
    
    final file = File(filePath);
    if (!await file.exists()) return false;
    
    final localHash = await calculateFileHash(file);
    return localHash != remoteHash;
  }

  /// 获取最后同步时间
  Future<DateTime?> getLastSyncTime(String configId) async {
    final file = File(path.join(_appDocDir.path, 'last_history_sync_$configId.txt'));
    if (await file.exists()) {
      final timestamp = await file.readAsString();
      return DateTime.fromMillisecondsSinceEpoch(int.parse(timestamp));
    }
    return null;
  }

  /// 保存最后同步时间
  Future<void> saveLastSyncTime(String configId, DateTime time) async {
    final file = File(path.join(_appDocDir.path, 'last_history_sync_$configId.txt'));
    await file.writeAsString(time.millisecondsSinceEpoch.toString());
  }
}