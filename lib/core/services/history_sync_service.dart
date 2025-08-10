import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:path/path.dart' show dirname;
import 'package:path_provider/path_provider.dart';

import '../../main.dart' show navigatorKey;
import '../../shared/models/dictation_session.dart';
import '../../shared/models/dictation_result.dart';
import '../../shared/widgets/conflict_resolution_dialog.dart';
import '../database/database_helper.dart';
import '../utils/file_hash_utils.dart';
import 'sync_service.dart';
import 'dictation_service.dart';
import 'image_sync_manager.dart';
import 'history_deletion_service.dart';
import 'device_id_service.dart';
import 'session_conflict_resolver.dart';

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
  final SessionConflictResolver _conflictResolver = SessionConflictResolver();
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
      
      // 收集图片文件信息（只有未删除的session才包含图片文件）
      final List<ImageFileInfo> imageFiles = [];
      final sessionDeleted = sessionMap['deleted'] == 1;
      
      if (!sessionDeleted) {
        // 只有未删除的session才收集图片文件信息
        final Map<String, String> imagePathToMd5 = {};
        for (final resultMap in resultMaps) {
          final originalPath = resultMap['original_image_path'] as String?;
          final originalMd5 = resultMap['original_image_md5'] as String?;
          final annotatedPath = resultMap['annotated_image_path'] as String?;
          final annotatedMd5 = resultMap['annotated_image_md5'] as String?;
          
          if (originalPath != null && originalPath.isNotEmpty && originalMd5 != null && originalMd5.isNotEmpty) {
            imagePathToMd5[originalPath] = originalMd5;
          }
          if (annotatedPath != null && annotatedPath.isNotEmpty && annotatedMd5 != null && annotatedMd5.isNotEmpty) {
            imagePathToMd5[annotatedPath] = annotatedMd5;
          }
        }

        for (final entry in imagePathToMd5.entries) {
          final imagePath = entry.key;
          final storedMd5 = entry.value;
          
          // 使用存储的MD5值构建ImageFileInfo，避免重复计算
          final imageInfo = await _imageSyncManager.getImageFileInfoWithMd5(imagePath, storedMd5, false);
          if (imageInfo != null) {
            imageFiles.add(imageInfo);
          }
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
  Future<SyncResult> importHistoryData(Map<String, dynamic> data, [SyncProvider? provider, VoidCallback? onImportComplete, void Function(String step, {int? current, int? total})? onProgress]) async {
    try {
      final syncData = HistorySyncData.fromMap(data);
      
      // 检测并解决冲突
      final conflicts = await _conflictResolver.detectAndResolveConflicts(syncData.sessions, syncData.deviceId, _deviceId);
      print('[HistorySync] 检测到 ${conflicts.length} 个冲突');
      for (final conflict in conflicts) {
        print('[HistorySync] 冲突: ${conflict.reason}');
      }

      // 创建冲突映射表，便于快速查找
      // 先收集所有需要用户选择的冲突
      final userChoiceConflicts = conflicts.where((conflict) => 
          conflict.resolution == ConflictResolution.requireUserChoice).toList();

      // 如果有需要用户选择的冲突，先处理用户选择
      if (userChoiceConflicts.isNotEmpty) {
        // 弹出用户选择对话框
        final result = await _showConflictResolutionDialog(userChoiceConflicts);
        if (result == null) {
          // 用户取消了操作
          throw Exception('用户取消了冲突解决操作');
        }
        
        // 直接更新conflict对象的resolution值
        for (final conflict in userChoiceConflicts) {
          final userChoice = result[conflict.sessionId];
          if (userChoice != null) {
            conflict.updateResolution(userChoice);
          }
        }
        print('[HistorySync] - 用户已选择 ${result.length} 个冲突的解决方案');
      }
      
      // 收集所有需要下载的图片文件信息（根据冲突解决结果判断）
      final Set<ImageFileInfo> allImageFiles = {};
      final Map<String, String> imagePathToMd5 = {};
      
      for (final sessionSync in syncData.sessions) {
        // 查找对应的冲突
        final conflict = conflicts.where((c) => c.sessionId == sessionSync.sessionId).firstOrNull;
        
        // 根据冲突解决结果获取最终的session状态
        DictationSession? finalSession;
        if (conflict != null) {
          finalSession = _conflictResolver.getSessionToApply(conflict);
        } else {
          // 没有冲突，使用远程session
          finalSession = DictationSession.fromMap(sessionSync.sessionData);
        }
        
        // 只有当最终session存在且未被删除时，才收集其图片文件
        if (finalSession != null && !finalSession.deleted) {
          // 从results中收集图片路径和MD5
          for (final resultMap in sessionSync.results) {
            final originalPath = resultMap['original_image_path'] as String?;
            final originalMd5 = resultMap['original_image_md5'] as String?;
            final annotatedPath = resultMap['annotated_image_path'] as String?;
            final annotatedMd5 = resultMap['annotated_image_md5'] as String?;
            
            if (originalPath != null && originalPath.isNotEmpty && originalMd5 != null && originalMd5.isNotEmpty) {
              imagePathToMd5[originalPath] = originalMd5;
            }
            if (annotatedPath != null && annotatedPath.isNotEmpty && annotatedMd5 != null && annotatedMd5.isNotEmpty) {
              imagePathToMd5[annotatedPath] = annotatedMd5;
            }
          }
        }
      }
      
      // 为每个图片路径创建ImageFileInfo
      for (final entry in imagePathToMd5.entries) {
        final imagePath = entry.key;
        final storedMd5 = entry.value;
        
        print("imagePath: $imagePath, storedMd5: $storedMd5");

        // 使用存储的MD5值构建ImageFileInfo
        final imageInfo = await _imageSyncManager.getImageFileInfoWithMd5(imagePath, storedMd5, true);
        if (imageInfo != null) {
          allImageFiles.add(imageInfo);
        }
      }
      
      print('[HistorySync] 导入历史记录：找到 ${syncData.sessions.length} 个会话');
      print('[HistorySync] 导入历史记录：需要下载 ${allImageFiles.length} 个图片文件');
      
      // 如果提供了同步提供者，下载图片文件
      if (provider != null && allImageFiles.isNotEmpty) {
        try {
          onProgress?.call('正在下载图片文件...', current: 0, total: allImageFiles.length);
          print('[HistorySync] 开始下载图片文件...');
          await _imageSyncManager.downloadMissingImages(allImageFiles.toList(), provider, data, onProgress: onProgress);
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
      
      // 注意：删除本地记录的逻辑现在由冲突检测和处理机制决定
      
      // 导入会话数据
      int importedSessions = 0;
      int importedResults = 0;
      
      for (final sessionSync in syncData.sessions) {
        final remoteSession = DictationSession.fromMap(sessionSync.sessionData);
        // 从conflicts列表中查找对应的冲突
        final conflict = conflicts.where((c) => c.sessionId == sessionSync.sessionId).firstOrNull;
        
        if (conflict == null) {
          // 没有冲突，直接创建新会话
          await _dictationService.createSession(remoteSession);
          if (!remoteSession.deleted) {
            importedSessions++;
          }
          
          // 导入结果
          for (final resultData in sessionSync.results) {
            final result = DictationResult.fromMap(resultData);
            await _dictationService.saveResult(result);
            importedResults++;
          }
        } else {
          // 有冲突，根据冲突解决方案处理
          print('[HistorySync] - 处理冲突: ${conflict.reason}');
          
          switch (conflict.resolution) {
            case ConflictResolution.useRemote:
              final sessionToUpdate = _conflictResolver.getSessionToApply(conflict);
              
              if (sessionToUpdate == null) {
                // 需要删除本地会话（使用公共的软删除方法）
                await _dictationService.deleteSession(conflict.localSession.sessionId);
                print('[HistorySync] - 软删除本地会话: ${conflict.localSession.sessionId}');
              } else {
                // 更新会话
                await _dictationService.updateSession(sessionToUpdate);
                print('[HistorySync] - 更新会话，新deleted状态=${sessionToUpdate.deleted}');
                
                // 如果会话被标记为删除，需要删除云端的笔迹文件
                if (sessionToUpdate.deleted) {
                  await _deleteCloudHandwritingFiles(conflict.localSession.sessionId, provider);
                }
                
                // 更新结果（简单起见，删除旧结果后重新插入）
                await _deleteSessionResults(sessionSync.sessionId);
                for (final resultData in sessionSync.results) {
                  final result = DictationResult.fromMap(resultData);
                  await _dictationService.saveResult(result);
                  importedResults++;
                }
              }
              break;
              
            case ConflictResolution.useLocal:
              print('[HistorySync] - 保留本地数据，跳过更新');
              // 如果本地会话被删除，也需要删除云端的笔迹文件
              if (conflict.localSession.deleted) {
                await _deleteCloudHandwritingFiles(conflict.localSession.sessionId, provider);
              }
              break;
              
            case ConflictResolution.requireUserChoice:
              // 这种情况不应该出现，因为已经在上面处理了
              throw Exception("未处理的用户选择冲突");
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

  /// 显示冲突解决对话框
  Future<Map<String, ConflictResolution>?> _showConflictResolutionDialog(
    List<SessionConflict> conflicts,
  ) async {
    // 需要获取当前的 BuildContext
    // 这里需要从调用方传入 context，或者使用全局导航器
    final context = _getNavigatorContext();
    if (context == null) {
      print('[HistorySync] - 无法获取 BuildContext，使用默认解决方案');
      // 如果无法获取 context，返回默认选择
      final defaultChoices = <String, ConflictResolution>{};
      for (final conflict in conflicts) {
        defaultChoices[conflict.sessionId] = ConflictResolution.useRemote;
      }
      return defaultChoices;
    }
    
    return await showConflictResolutionDialog(context, conflicts);
  }
  
  /// 删除云端笔迹文件
  Future<void> _deleteCloudHandwritingFiles(String sessionId, [SyncProvider? provider]) async {
    // todo::
    // try {
    //   print('[HistorySync] - 开始删除会话 $sessionId 的云端笔迹文件');
      
    //   // 获取会话的所有结果数据，收集笔迹文件信息
    //   final results = await _dictationService.getSessionResults(sessionId);
    //   final imageObjectKeys = <String>{};
      
    //   for (final result in results) {
    //     // 根据本地图片路径和MD5生成云端对象键
    //     if (result.originalImagePath != null && result.originalImagePath!.isNotEmpty && 
    //         result.originalImageMd5 != null && result.originalImageMd5!.isNotEmpty) {
    //       final objectKey = FileHashUtils.generateCloudObjectKey(result.originalImagePath!, result.originalImageMd5!);
    //       imageObjectKeys.add(objectKey);
    //     }
        
    //     if (result.annotatedImagePath != null && result.annotatedImagePath!.isNotEmpty && 
    //         result.annotatedImageMd5 != null && result.annotatedImageMd5!.isNotEmpty) {
    //       final objectKey = FileHashUtils.generateCloudObjectKey(result.annotatedImagePath!, result.annotatedImageMd5!);
    //       imageObjectKeys.add(objectKey);
    //     }
    //   }
      
    //   if (imageObjectKeys.isEmpty) {
    //     print('[HistorySync] - 会话 $sessionId 没有关联的笔迹文件');
    //     return;
    //   }
      
    //   print('[HistorySync] - 找到 ${imageObjectKeys.length} 个笔迹文件需要删除');
      
    //   // 如果提供了同步提供商，删除云端文件
    //   if (provider != null) {
    //     int deletedCount = 0;
    //     for (final objectKey in imageObjectKeys) {
    //       try {
    //         // 使用提供商的公共方法删除对象
    //         final deleteResult = await provider.deleteObjectByKey(objectKey);
    //         if (deleteResult.success) {
    //           deletedCount++;
    //           print('[HistorySync] - 删除云端笔迹文件成功: $objectKey');
    //         } else {
    //           print('[HistorySync] - 删除云端笔迹文件失败: $objectKey, ${deleteResult.message}');
    //         }
    //       } catch (e) {
    //         print('[HistorySync] - 删除云端笔迹文件异常: $objectKey, $e');
    //       }
    //     }
        
    //     print('[HistorySync] - 云端笔迹文件删除完成，成功删除 $deletedCount/${imageObjectKeys.length} 个文件');
    //   } else {
    //     print('[HistorySync] - 当前同步提供商不支持删除云端文件');
    //   }
    // } catch (e) {
    //   print('[HistorySync] - 删除云端笔迹文件时发生异常: $e');
    //   // 不抛出异常，允许同步操作继续进行
    // }
  }
  
  /// 获取导航器上下文
  BuildContext? _getNavigatorContext() {
    return navigatorKey.currentContext;
  }

}