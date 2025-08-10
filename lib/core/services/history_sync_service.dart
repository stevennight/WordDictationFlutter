import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path/path.dart' show dirname;
import 'package:path_provider/path_provider.dart';

import '../../shared/models/dictation_session.dart';
import '../../shared/models/dictation_result.dart';
import '../database/database_helper.dart';
import 'sync_service.dart';
import 'dictation_service.dart';
import 'image_sync_manager.dart';
import 'history_deletion_service.dart';
import 'device_id_service.dart';

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
  final List<Map<String, dynamic>> sessionWords;
  final List<ImageFileInfo> imageFiles;

  SessionSyncData({
    required this.sessionId,
    required this.lastModified,
    required this.sessionData,
    required this.results,
    required this.sessionWords,
    required this.imageFiles,
  });

  Map<String, dynamic> toMap() {
    return {
      'sessionId': sessionId,
      'lastModified': lastModified.toIso8601String(),
      'sessionData': sessionData,
      'results': results,
      'sessionWords': sessionWords,
      'imageFiles': imageFiles.map((f) => f.toMap()).toList(),
    };
  }

  factory SessionSyncData.fromMap(Map<String, dynamic> map) {
    return SessionSyncData(
      sessionId: map['sessionId'],
      lastModified: DateTime.parse(map['lastModified']),
      sessionData: Map<String, dynamic>.from(map['sessionData']),
      results: List<Map<String, dynamic>>.from(map['results']),
      sessionWords: List<Map<String, dynamic>>.from(map['sessionWords'] ?? []),
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
  final HistoryDeletionService _deletionService = HistoryDeletionService();
  final DeviceIdService _deviceIdService = DeviceIdService();
  late ImageSyncManager _imageSyncManager;
  late String _deviceId;
  late Directory _appDocDir;
  late Directory _syncCacheDir;

  /// 初始化服务
  Future<void> initialize() async {
    // 初始化设备ID服务
    await _deviceIdService.initialize();
    _deviceId = await _deviceIdService.getDeviceId();
    
    // For desktop platforms, use executable directory
    // For mobile platforms, fallback to documents directory
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      // Get executable directory for desktop platforms
      final executablePath = Platform.resolvedExecutable;
      _appDocDir = Directory(dirname(executablePath));
    } else {
      // Fallback to documents directory for mobile platforms
      _appDocDir = await getApplicationDocumentsDirectory();
    }
    
    // 初始化sync_cache目录
    _syncCacheDir = Directory(path.join(_appDocDir.path, 'sync_cache'));
    if (!await _syncCacheDir.exists()) {
      await _syncCacheDir.create(recursive: true);
    }
    
    _imageSyncManager = ImageSyncManager();
    await _imageSyncManager.initialize();
  }

  /// 获取sync_cache目录路径
  String get _syncCachePath => _syncCacheDir.path;

  /// 获取设备ID
  String get deviceId => _deviceId;

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
    
    // 使用getAllSessionsIncludingDeleted获取包括已删除的会话
    final allSessions = await _dictationService.getAllSessionsIncludingDeleted();
    
    // 根据条件过滤会话
    final filteredSessions = allSessions.where((session) {
      // 排除进行中的会话
      if (session.status.index == 0) return false; // inProgress
      
      // 如果指定了since时间，只包含该时间之后的会话
      if (since != null && !session.startTime.isAfter(since)) {
        return false;
      }
      
      return true;
    }).toList();
    
    // 转换为Map格式以保持兼容性
    final sessionMaps = filteredSessions.map((session) => session.toMap()).toList();

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
      
      // Note: session_words operations removed as table no longer exists
      
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
        sessionWords: [], // Note: session_words operations removed as table no longer exists
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
  Future<SyncResult> importHistoryData(Map<String, dynamic> data, [SyncProvider? provider, VoidCallback? onImportComplete]) async {
    try {
      final syncData = HistorySyncData.fromMap(data);
      
      // 检测冲突
      final conflicts = await _detectConflicts(syncData);
      if (conflicts.isNotEmpty) {
        return SyncResult.failure('检测到冲突: ${conflicts.join(", ")}');
      }
      
      // 收集所有需要下载的图片文件信息
      final Set<ImageFileInfo> allImageFiles = {};
      for (final sessionSync in syncData.sessions) {
        allImageFiles.addAll(sessionSync.imageFiles);
      }
      
      print('[HistorySync] 导入历史记录：找到 ${syncData.sessions.length} 个会话');
      print('[HistorySync] 导入历史记录：需要下载 ${allImageFiles.length} 个图片文件');
      
      // 如果提供了同步提供者，下载图片文件
      if (provider != null && allImageFiles.isNotEmpty) {
        try {
          print('[HistorySync] 开始下载图片文件...');
          await _imageSyncManager.downloadMissingImages(allImageFiles.toList(), provider, data);
          print('[HistorySync] 图片文件下载完成');
        } catch (e) {
          print('[HistorySync] 下载图片文件时出错: $e');
          // 继续导入历史记录数据，不因图片下载失败而中断
        }
      } else if (provider == null) {
        print('[HistorySync] 未提供同步提供者，跳过图片下载');
      } else {
        print('[HistorySync] 没有需要下载的图片文件');
      }
      
      // 删除本地存在但远端不存在的记录（实现真正的同步）
      await _deletionService.deleteLocalOnlyRecords(syncData.sessions.map((s) => s.sessionId).toSet());
      
      // 导入会话数据
      int importedSessions = 0;
      int importedResults = 0;
      final db = await _dbHelper.database;
      
      for (final sessionSync in syncData.sessions) {
        // 检查会话是否已存在（包括已删除的会话）
        final existingSessions = await _dictationService.getAllSessionsIncludingDeleted();
        DictationSession? existingSession;
        try {
          existingSession = existingSessions.firstWhere(
            (s) => s.sessionId == sessionSync.sessionId,
          );
        } catch (e) {
          existingSession = null;
        }
        
        final remoteSession = DictationSession.fromMap(sessionSync.sessionData);
        
        // 调试日志：检查远端数据格式
        print('[HistorySync] 处理会话 ${remoteSession.sessionId}:');
        print('[HistorySync] - 远端数据包含deleted字段: ${sessionSync.sessionData.containsKey('deleted')}');
        print('[HistorySync] - 远端deleted值: ${sessionSync.sessionData['deleted']}');
        print('[HistorySync] - 解析后deleted状态: ${remoteSession.deleted}');
        
        if (existingSession == null) {
          // 创建新会话（包括可能的删除状态）
          await _dictationService.createSession(remoteSession);
          if (!remoteSession.deleted) {
            importedSessions++;
          }
          print('[HistorySync] - 创建新会话，deleted=${remoteSession.deleted}');
          
          // 如果远程会话未删除，导入结果和单词关联
          if (!remoteSession.deleted) {
            // 导入结果
            for (final resultData in sessionSync.results) {
              final result = DictationResult.fromMap(resultData);
              await _dictationService.saveResult(result);
              importedResults++;
            }
            
            // Note: session_words operations removed as table no longer exists
          }
        } else {
          // 检查是否需要更新
          final existingModified = existingSession.startTime;
          final remoteModified = remoteSession.deletedAt ?? remoteSession.startTime;
          
          print('[HistorySync] - 本地已存在会话，本地deleted=${existingSession.deleted}');
          print('[HistorySync] - 删除状态是否不同: ${remoteSession.deleted != existingSession.deleted}');
          
          // 处理删除状态冲突：保留最新的删除操作
          bool shouldUpdate = false;
          DictationSession sessionToUpdate = remoteSession;
          
          if (remoteSession.deleted != existingSession.deleted) {
            // 删除状态不同，需要比较删除时间
            if (remoteSession.deleted && existingSession.deleted) {
              // 两边都删除了，比较删除时间，保留最新的
              final remoteDeletedAt = remoteSession.deletedAt;
              final existingDeletedAt = existingSession.deletedAt;
              if (remoteDeletedAt != null && existingDeletedAt != null) {
                shouldUpdate = remoteDeletedAt.isAfter(existingDeletedAt);
              } else if (remoteDeletedAt != null) {
                shouldUpdate = true;
              }
            } else if (remoteSession.deleted && !existingSession.deleted) {
              // 远端删除了，本地没删除，使用远端的删除状态
              shouldUpdate = true;
            } else if (!remoteSession.deleted && existingSession.deleted) {
              // 本地删除了，远端没删除，保留本地的删除状态
              sessionToUpdate = existingSession;
              shouldUpdate = false;
              print('[HistorySync] - 保留本地删除状态，不更新');
            }
          } else if (sessionSync.lastModified.isAfter(existingModified)) {
            // 删除状态相同，但远端数据更新，正常更新
            shouldUpdate = true;
          }
          
          if (shouldUpdate) {
            // 更新会话（包括删除状态）
            await _dictationService.updateSession(sessionToUpdate);
            print('[HistorySync] - 更新会话，新deleted状态=${sessionToUpdate.deleted}');
            
            // 如果更新后的会话未删除，更新结果和单词关联
            if (!sessionToUpdate.deleted) {
              // 更新结果（简单起见，删除旧结果后重新插入）
              await _deleteSessionResults(sessionSync.sessionId);
              for (final resultData in sessionSync.results) {
                final result = DictationResult.fromMap(resultData);
                await _dictationService.saveResult(result);
                importedResults++;
              }
              
              // Note: session_words operations removed as table no longer exists
            }
          }
        }
      }
      
      // 导入完成后调用回调
      if (onImportComplete != null) {
        onImportComplete();
      }
      
      return SyncResult.success(
        message: '成功导入 $importedSessions 个会话，$importedResults 个结果，${allImageFiles.length} 个图片文件',
        data: {
          'importedSessions': importedSessions,
          'importedResults': importedResults,
          'downloadedImages': allImageFiles.length,
        },
      );
    } catch (e) {
      return SyncResult.failure('导入历史记录失败: $e');
    }
  }

  /// 导入历史记录数据（用于下载，不删除本地记录）
  Future<SyncResult> importHistoryDataWithoutDelete(Map<String, dynamic> data, [SyncProvider? provider, VoidCallback? onImportComplete]) async {
    try {
      final syncData = HistorySyncData.fromMap(data);
      
      // 检测冲突
      final conflicts = await _detectConflicts(syncData);
      if (conflicts.isNotEmpty) {
        return SyncResult.failure('检测到冲突: ${conflicts.join(", ")}');
      }
      
      // 收集所有需要下载的图片文件信息
      final Set<ImageFileInfo> allImageFiles = {};
      for (final sessionSync in syncData.sessions) {
        allImageFiles.addAll(sessionSync.imageFiles);
      }
      
      print('[HistorySync] 导入历史记录（不删除本地记录）：找到 ${syncData.sessions.length} 个会话');
      print('[HistorySync] 导入历史记录（不删除本地记录）：需要下载 ${allImageFiles.length} 个图片文件');
      
      // 如果提供了同步提供者，下载图片文件
      if (provider != null && allImageFiles.isNotEmpty) {
        try {
          print('[HistorySync] 开始下载图片文件...');
          await _imageSyncManager.downloadMissingImages(allImageFiles.toList(), provider, data);
          print('[HistorySync] 图片文件下载完成');
        } catch (e) {
          print('[HistorySync] 下载图片文件时出错: $e');
          // 继续导入历史记录数据，不因图片下载失败而中断
        }
      } else if (provider == null) {
        print('[HistorySync] 未提供同步提供者，跳过图片下载');
      } else {
        print('[HistorySync] 没有需要下载的图片文件');
      }
      
      // 注意：这里不调用 _deleteLocalOnlyRecords 方法
      
      // 导入会话数据
      int importedSessions = 0;
      int importedResults = 0;
      final db = await _dbHelper.database;
      
      for (final sessionSync in syncData.sessions) {
        // 检查会话是否已存在（包括已删除的会话）
        final existingSessions = await _dictationService.getAllSessionsIncludingDeleted();
        DictationSession? existingSession;
        try {
          existingSession = existingSessions.firstWhere(
            (s) => s.sessionId == sessionSync.sessionId,
          );
        } catch (e) {
          existingSession = null;
        }
        
        final remoteSession = DictationSession.fromMap(sessionSync.sessionData);
        
        if (existingSession == null) {
          // 创建新会话（包括可能的删除状态）
          await _dictationService.createSession(remoteSession);
          if (!remoteSession.deleted) {
            importedSessions++;
          }
          
          // 如果远程会话未删除，导入结果和单词关联
          if (!remoteSession.deleted) {
            // 导入结果
            for (final resultData in sessionSync.results) {
              final result = DictationResult.fromMap(resultData);
              await _dictationService.saveResult(result);
              importedResults++;
            }
            
            // Note: session_words operations removed as table no longer exists
          }
        } else {
          // 检查是否需要更新
          final existingModified = existingSession.startTime;
          final remoteModified = remoteSession.deletedAt ?? remoteSession.startTime;
          
          // 处理删除状态冲突：保留最新的删除操作
          bool shouldUpdate = false;
          DictationSession sessionToUpdate = remoteSession;
          
          if (remoteSession.deleted != existingSession.deleted) {
            // 删除状态不同，需要比较删除时间
            if (remoteSession.deleted && existingSession.deleted) {
              // 两边都删除了，比较删除时间，保留最新的
              final remoteDeletedAt = remoteSession.deletedAt;
              final existingDeletedAt = existingSession.deletedAt;
              if (remoteDeletedAt != null && existingDeletedAt != null) {
                shouldUpdate = remoteDeletedAt.isAfter(existingDeletedAt);
              } else if (remoteDeletedAt != null) {
                shouldUpdate = true;
              }
            } else if (remoteSession.deleted && !existingSession.deleted) {
              // 远端删除了，本地没删除，使用远端的删除状态
              shouldUpdate = true;
            } else if (!remoteSession.deleted && existingSession.deleted) {
              // 本地删除了，远端没删除，保留本地的删除状态
              sessionToUpdate = existingSession;
              shouldUpdate = false;
              print('[HistorySync] - 保留本地删除状态，不更新');
            }
          } else if (sessionSync.lastModified.isAfter(existingModified)) {
            // 删除状态相同，但远端数据更新，正常更新
            shouldUpdate = true;
          }
          
          if (shouldUpdate) {
            // 更新会话（包括删除状态）
            await _dictationService.updateSession(sessionToUpdate);
            
            // 如果更新后的会话未删除，更新结果和单词关联
            if (!sessionToUpdate.deleted) {
              // 更新结果（简单起见，删除旧结果后重新插入）
              await _deleteSessionResults(sessionSync.sessionId);
              for (final resultData in sessionSync.results) {
                final result = DictationResult.fromMap(resultData);
                await _dictationService.saveResult(result);
                importedResults++;
              }
              
              // Note: session_words operations removed as table no longer exists
            }
          }
        }
      }
      
      // 导入完成后调用回调
      if (onImportComplete != null) {
        onImportComplete();
      }
      
      return SyncResult.success(
        message: '成功导入 $importedSessions 个会话，$importedResults 个结果，${allImageFiles.length} 个图片文件（不删除本地记录）',
        data: {
          'importedSessions': importedSessions,
          'importedResults': importedResults,
          'downloadedImages': allImageFiles.length,
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

  /// 删除会话结果和单词关联
  Future<void> _deleteSessionResults(String sessionId) async {
    // 使用统一的删除服务删除会话结果和单词关联（不删除图片文件，因为可能还需要用于同步）
    await _deletionService.deleteSessionResults(sessionId, deleteImages: false);
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
    final file = File(path.join(_syncCachePath, 'last_history_sync_$configId.txt'));
    if (await file.exists()) {
      final timestamp = await file.readAsString();
      return DateTime.fromMillisecondsSinceEpoch(int.parse(timestamp));
    }
    return null;
  }

  /// 保存最后同步时间
  Future<void> saveLastSyncTime(String configId, DateTime time) async {
    final file = File(path.join(_syncCachePath, 'last_history_sync_$configId.txt'));
    await file.writeAsString(time.millisecondsSinceEpoch.toString());
  }


}