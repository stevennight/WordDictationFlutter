import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_word_dictation/shared/utils/path_utils.dart';
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
import 'history_file_sync_manager.dart';
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

  SessionSyncData({
    required this.sessionId,
    required this.lastModified,
    required this.sessionData,
    required this.results,
    required this.sessionWords,
  });

  Map<String, dynamic> toMap() {
    return {
      'sessionId': sessionId,
      'lastModified': lastModified.toIso8601String(),
      'sessionData': sessionData,
      'results': results,
      'sessionWords': sessionWords,
    };
  }

  factory SessionSyncData.fromMap(Map<String, dynamic> map) {
    return SessionSyncData(
      sessionId: map['sessionId'],
      lastModified: DateTime.parse(map['lastModified']),
      sessionData: Map<String, dynamic>.from(map['sessionData']),
      results: List<Map<String, dynamic>>.from(map['results']),
      sessionWords: List<Map<String, dynamic>>.from(map['sessionWords'] ?? []),
    );
  }
}

/// 图片文件信息
class ImageFileInfo {
  final String filePath;
  final String hash;
  final int size;
  final DateTime lastModified;

  ImageFileInfo({
    required this.filePath,
    required this.hash,
    required this.size,
    required this.lastModified,
  });

  Map<String, dynamic> toMap() {
    return {
      'filePath': filePath,
      'hash': hash,
      'size': size,
      'lastModified': lastModified.toIso8601String(),
    };
  }

  factory ImageFileInfo.fromMap(Map<String, dynamic> map) {
    return ImageFileInfo(
      filePath: map['filePath'],
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
  late HistoryFileSyncManager _historyFileSyncManager;
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
    
    _historyFileSyncManager = HistoryFileSyncManager();
    await _historyFileSyncManager.initialize();
  }

  /// 获取设备ID
  String get deviceId => _deviceId;

  /// 导出历史记录数据（用于上传）
  Future<Map<String, dynamic>> exportHistoryData({DateTime? since}) async {
    final db = await _dbHelper.database;
    
    // 查询会话数据
    // String whereClause = "status != 'inProgress'";
    // List<dynamic> whereArgs = [];
    //
    // if (since != null) {
    //   whereClause += " AND start_time > ?";
    //   whereArgs.add(since.millisecondsSinceEpoch);
    // }
    
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
      
      sessions.add(SessionSyncData(
        sessionId: sessionId,
        lastModified: DateTime.fromMillisecondsSinceEpoch(
          sessionMap['start_time'] as int,
        ),
        sessionData: Map<String, dynamic>.from(sessionMap),
        results: resultMaps.map((r) => Map<String, dynamic>.from(r)).toList(),
        sessionWords: [], // Note: session_words operations removed as table no longer exists
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
      final Map<String, String> imagePathToObjectKey = {};
      
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
          for (final resultMap in syncData.sessions.where((s) => s.sessionId == sessionSync.sessionId).first.results) {
            final originalPath = resultMap['original_image_path'] as String?;
            final originalMd5 = resultMap['original_image_md5'] as String?;
            final annotatedPath = resultMap['annotated_image_path'] as String?;
            final annotatedMd5 = resultMap['annotated_image_md5'] as String?;
            
            if (originalPath != null && originalPath.isNotEmpty && originalMd5 != null && originalMd5.isNotEmpty) {
              imagePathToMd5[originalPath] = originalMd5;
              // 生成对象键
              final generatedObjectKey = FileHashUtils.generateCloudObjectKey(originalPath, originalMd5);
              imagePathToObjectKey[originalPath] = generatedObjectKey;
            }
            if (annotatedPath != null && annotatedPath.isNotEmpty && annotatedMd5 != null && annotatedMd5.isNotEmpty) {
              imagePathToMd5[annotatedPath] = annotatedMd5;
              // 生成对象键
              final generatedObjectKey = FileHashUtils.generateCloudObjectKey(annotatedPath, annotatedMd5);
              imagePathToObjectKey[annotatedPath] = generatedObjectKey;
            }
          }
        }
      }
      
      print('[HistorySync] 从冲突解决后的数据中找到 ${imagePathToObjectKey.length} 个图片对象键');
      print('[HistorySync] 从冲突解决后的数据中找到 ${imagePathToMd5.length} 个图片MD5');
      
      // 检查哪些图片需要下载（本地不存在或MD5不匹配）
      for (final entry in imagePathToMd5.entries) {
        final imagePath = entry.key;
        final storedMd5 = entry.value;
        
        print("[HistorySync] 检查图片: $imagePath, storedMd5: $storedMd5");
        
        // 检查本地文件是否存在以及MD5是否匹配
        final absolutedImagePath = await PathUtils.convertToAbsolutePath(imagePath);
        final localFile = File(absolutedImagePath);
        final expectedMd5 = imagePathToMd5[imagePath]!;
        
        bool needDownload = false;
        if (!localFile.existsSync()) {
          print('[HistorySync] 本地文件不存在，需要下载: $absolutedImagePath');
          needDownload = true;
        } else {
          // 检查MD5是否匹配
          needDownload = await FileHashUtils.needsSync(absolutedImagePath, expectedMd5);
          print('[HistorySync] 根据文件MD5判断是否需要同步: ${needDownload.toString()}');
        }
        
        // 只有需要下载的图片才创建ImageFileInfo
        if (needDownload) {
          final imageInfo = await _historyFileSyncManager.getImageFileInfoWithMd5(imagePath, storedMd5, true);
          if (imageInfo != null) {
            allImageFiles.add(imageInfo);
          }
        }
      }
      
      print('[HistorySync] 导入历史记录：找到 ${syncData.sessions.length} 个会话');
      print('[HistorySync] 导入历史记录：需要下载 ${allImageFiles.length} 个图片文件');
      
      // 如果提供了同步提供者，下载图片文件
      if (provider != null && allImageFiles.isNotEmpty) {
        try {
          onProgress?.call('正在下载图片文件...', current: 0, total: allImageFiles.length);
          print('[HistorySync] 开始下载图片文件...');
          await _downloadImageFiles(allImageFiles.toList(), provider, imagePathToObjectKey, onProgress);
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
          DictationSession? sessionToUpdate = _conflictResolver.getSessionToApply(conflict);
          
          switch (conflict.resolution) {
            case ConflictResolution.useRemote:
              
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
                  await _deleteCloudHandwritingFilesFromResults(sessionSync.results, provider);
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
              if (sessionToUpdate != null && sessionToUpdate.deleted) {
                await _deleteCloudHandwritingFilesFromResults(sessionSync.results, provider);
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

  /// 智能同步历史记录数据（双向合并同步）
  Future<SyncResult> smartSyncHistory(String configId, {
    VoidCallback? onImportComplete,
    void Function(String step, {int? current, int? total})? onProgress,
  }) async {
    try {
      print('[HistorySyncService] 开始智能同步历史记录');
      
      // 需要从SyncService获取provider
      final syncService = SyncService();
      final provider = syncService.getProvider(configId);
      if (provider == null) {
        return SyncResult.failure('同步配置不存在');
      }

      // 1. 获取本地历史记录数据
      onProgress?.call('正在获取本地历史记录数据...');
      print('[HistorySyncService] 第一步：获取本地历史记录数据');
      final localHistoryData = await exportHistoryData();
      final localSessions = localHistoryData['sessions'] as List<dynamic>;
      print('[HistorySyncService] 本地会话数量: ${localSessions.length}');
      
      // 2. 尝试下载远端记录
      onProgress?.call('正在下载云端历史记录...');
      print('[HistorySyncService] 第二步：下载远端记录');
      final downloadResult = await downloadData(provider, SyncDataType.history);
      
      Map<String, dynamic> remoteHistoryData;
      List<dynamic> remoteSessions;
      
      if (!downloadResult.success) {
        // 如果是文件不存在错误，说明是首次同步，创建空的远端数据
        if (downloadResult.message?.contains('文件不存在') == true || downloadResult.message?.contains('404') == true) {
          print('[HistorySyncService] 远端文件不存在，这是首次同步');
          remoteHistoryData = {'sessions': []};
          remoteSessions = [];
        } else {
          print('[HistorySyncService] 下载远端记录失败: ${downloadResult.message}');
          return downloadResult;
        }
      } else {
        remoteHistoryData = downloadResult.data!;
        remoteSessions = remoteHistoryData['sessions'] as List<dynamic>;
        print('[HistorySyncService] 远端会话数量: ${remoteSessions.length}');
      }
      
      // 3. 执行双向合并
      onProgress?.call('正在合并本地和云端数据...');
      print('[HistorySyncService] 第三步：执行双向合并');
      
      // 将远端数据合并到本地（包括处理软删除）
      if (remoteSessions.isNotEmpty) {
        final importResult = await importHistoryData(
          remoteHistoryData, 
          provider, 
          onImportComplete,
          onProgress
        );
        if (!importResult.success) {
          print('[HistorySyncService] 导入远端记录失败: ${importResult.message}');
          return importResult;
        }
      }
      
      // 4. 获取合并后的本地数据并上传到远端
      onProgress?.call('正在上传合并后的数据到云端...');
      print('[HistorySyncService] 第四步：上传合并后的数据到远端');
      final mergedHistoryData = await exportHistoryData();

      final uploadResult = await _uploadHistoryData(provider, remoteSessions, mergedHistoryData, onProgress);

      
      if (uploadResult.success) {
        // 更新配置中的同步时间
        final config = syncService.getConfig(configId);
        if (config != null) {
          final updatedConfig = SyncConfig(
            id: config.id,
            name: config.name,
            providerType: config.providerType,
            settings: config.settings,
            autoSync: config.autoSync,
            syncInterval: config.syncInterval,
            lastSyncTime: DateTime.now(),
            enabled: config.enabled,
          );
          await syncService.addConfig(updatedConfig);
        }
        
        print('[HistorySyncService] 智能同步完成');
        return SyncResult.success(message: '智能同步完成');
      } else {
        print('[HistorySyncService] 上传合并后的记录失败: ${uploadResult.message}');
        return uploadResult;
      }
    } catch (e) {
      print('[HistorySyncService] 智能同步过程中发生错误: $e');
      return SyncResult.failure('智能同步失败: $e');
    }
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
  /// [objectKey] 要删除的对象键
  /// [provider] 同步提供者，如果未提供则使用默认提供者
  Future<void> _deleteCloudHandwritingFile(String objectKey, [SyncProvider? provider]) async {
    try {
      final syncProvider = provider;
      if (syncProvider == null) {
        debugPrint('同步提供者未初始化，无法删除云端文件: $objectKey');
        return;
      }
      
      // 使用对象存储同步提供者删除文件
      final result = await syncProvider.deleteFile(objectKey);
      if (result.success) {
        debugPrint('成功删除云端文件: $objectKey');
      } else {
        debugPrint('删除云端文件失败: $objectKey, ${result.message}');
      }
    } catch (e) {
      debugPrint('删除云端文件异常: $objectKey, $e');
    }
  }

  /// 从结果列表中删除云端笔迹文件
  Future<void> _deleteCloudHandwritingFilesFromResults(List<Map<String, dynamic>> results, SyncProvider? provider) async {
    for (final resultMap in results) {
      // 删除原始图片文件
      final originalPath = resultMap['original_image_path'] as String?;
      if (originalPath != null && originalPath.isNotEmpty) {
        await _deleteCloudHandwritingFile(originalPath, provider);
      }
      
      // 删除标注图片文件
      final annotatedPath = resultMap['annotated_image_path'] as String?;
      if (annotatedPath != null && annotatedPath.isNotEmpty) {
        await _deleteCloudHandwritingFile(annotatedPath, provider);
      }
    }
  }
  
  /// 上传历史记录数据（包含图片文件）
  Future<SyncResult> _uploadHistoryData(SyncProvider provider, List<dynamic> remoteSessions, Map<String, dynamic> mergeHistoryData, void Function(String step, {int? current, int? total})? onProgress) async {
    try {
      print('[HistorySync] 开始上传历史记录数据');
      
      final sessions = mergeHistoryData['sessions'] as List<dynamic>? ?? [];

      // 整理文件路径 => md5的map
      final filePathMd5Map = <String, String>{};
      for (final session in remoteSessions) {
        final sessionMap = session as Map<String, dynamic>;
        final results = sessionMap['results'] as List<dynamic>? ?? [];

        for (final result in results) {
          final resultMap = result as Map<String, dynamic>;
          final originalPath = resultMap['original_image_path'] as String?;
          final originalMd5 = resultMap['original_image_md5'] as String?;
          if (originalPath != null && originalPath.isNotEmpty && originalMd5 != null && originalMd5.isNotEmpty) {
            filePathMd5Map[originalPath] = originalMd5;
          }
          final annotatedPath = resultMap['annotated_image_path'] as String?;
          final annotatedMd5 = resultMap['annotated_image_md5'] as String?;
          if (annotatedPath != null && annotatedPath.isNotEmpty && annotatedMd5 != null && annotatedMd5.isNotEmpty) {
            filePathMd5Map[annotatedPath] = annotatedMd5;
          }
        }
      }

      // 首先收集所有需要上传的图片文件
      final imagesToUpload = <String>{};
      
      for (final session in sessions) {
        final sessionMap = session as Map<String, dynamic>;
        final results = sessionMap['results'] as List<dynamic>? ?? [];
        
        for (final result in results) {
          final resultMap = result as Map<String, dynamic>;
          
          if (sessionMap['sessionData']['deleted'] == 1) {
            continue;
          }

          // 比较原来远端的文件md5和本地文件的md5，不一致则上传
          final originalPath = resultMap['original_image_path'] as String?;
          final annotatedPath = resultMap['annotated_image_path'] as String?;
          final originalMd5 = resultMap['original_image_md5'] as String?;
          final annotatedMd5 = resultMap['annotated_image_md5'] as String?;

          // 判断远端文件是否存在
          if (originalPath != null && originalPath.isNotEmpty) {
            final originalMd5InRemote = filePathMd5Map[originalPath];
            bool originalUpload = true;
            if (originalMd5 != null && originalMd5.isNotEmpty && originalMd5InRemote != null && originalMd5InRemote.isNotEmpty) {
              if (originalMd5 == originalMd5InRemote) {
                originalUpload = false;
              }
            }

            if (originalUpload || !await provider.fileExists(originalPath)) {
              imagesToUpload.add(originalPath);
            }
          }
          if (annotatedPath != null && annotatedPath.isNotEmpty) {
            final annotatedMd5InRemote = filePathMd5Map[annotatedPath];
            bool annotatedUpload = true;
            if (annotatedMd5 != null && annotatedMd5.isNotEmpty && annotatedMd5InRemote != null && annotatedMd5InRemote.isNotEmpty) {
              if (annotatedMd5 == annotatedMd5InRemote) {
                annotatedUpload = false;
              }
            }

            if (annotatedUpload && !await provider.fileExists(annotatedPath)) {
              imagesToUpload.add(annotatedPath);
            }
          }
        }
      }
      
      print('[HistorySync] 找到 ${imagesToUpload.length} 个图片文件需要上传');
      
      // 上传图片文件
      final uploadedImages = <String, String>{}; // 原路径 -> 对象键
      
      for (final imagePath in imagesToUpload) {
        onProgress?.call('正在上传图片: $imagePath', current: uploadedImages.length, total: imagesToUpload.length);

        try {
          // 上传图片文件到云端
          final uploadResult = await _uploadSingleImage(imagePath, provider);
          if (uploadResult != null) {
            uploadedImages[imagePath] = uploadResult;
            print('[HistorySync] 图片上传成功: $imagePath -> $uploadResult');
          } else {
            print('[HistorySync] 图片上传失败: $imagePath');
          }
        } catch (e) {
          print('[HistorySync] 上传图片异常: $imagePath, 错误: $e');
        }
      }
      
      print('[HistorySync] 成功上传 ${uploadedImages.length} 个图片文件');
      
      // 更新历史记录数据中的图片路径为对象键
      final updatedData = Map<String, dynamic>.from(mergeHistoryData);
      final updatedSessions = <Map<String, dynamic>>[];
      
      for (final session in sessions) {
        final sessionMap = Map<String, dynamic>.from(session as Map<String, dynamic>);
        final results = sessionMap['results'] as List<dynamic>? ?? [];
        final updatedResults = <Map<String, dynamic>>[];
        
        for (final result in results) {
          final resultMap = Map<String, dynamic>.from(result as Map<String, dynamic>);
          
          // 更新图片路径为对象键
          final originalPath = resultMap['original_image_path'] as String?;
          final annotatedPath = resultMap['annotated_image_path'] as String?;
          
          if (originalPath != null && uploadedImages.containsKey(originalPath)) {
            resultMap['original_image_object_key'] = uploadedImages[originalPath];
          }
          if (annotatedPath != null && uploadedImages.containsKey(annotatedPath)) {
            resultMap['annotated_image_object_key'] = uploadedImages[annotatedPath];
          }
          
          updatedResults.add(resultMap);
        }
        
        sessionMap['results'] = updatedResults;
        updatedSessions.add(sessionMap);
      }
      
      updatedData['sessions'] = updatedSessions;

      // 对于其他数据类型，委托给 provider 处理
      const dataType = SyncDataType.history;
      _logDebug('开始上传数据，类型: $dataType');

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final dataTypeName = dataType.toString().split('.').last;
      final objectKey = "$dataTypeName-$timestamp.json";
      final latestKey = "$dataTypeName-latest.json";
      final jsonData = jsonEncode(mergeHistoryData);
      final bytes = utf8.encode(jsonData);

      _logDebug('上传JSON数据，大小: ${bytes.length} bytes');

      // 上传带时间戳的文件
      final uploadResult = await provider.uploadBytes(bytes, objectKey);
      if (!uploadResult.success) {
        _logDebug('上传主文件失败: ${uploadResult.message}');
        return uploadResult;
      }

      // 同时上传latest文件作为最新版本的快速访问
      final latestResult = await provider.uploadBytes(bytes, latestKey);
      if (!latestResult.success) {
        _logDebug('上传latest文件失败: ${latestResult.message}');
        return SyncResult.failure('上传latest文件失败: ${latestResult.message}');
      }

      _logDebug('历史记录数据上传完成');

      return SyncResult.success(
        message: '历史记录上传成功',
        data: {
          'objectKey': objectKey,
          'latestKey': latestKey,
          'uploadedImages': uploadedImages.length,
          'totalImages': imagesToUpload.length,
        },
      );
    } catch (e) {
      print('[HistorySync] 上传历史记录数据异常: $e');
      return SyncResult.failure('上传历史记录数据失败: $e');
    }
  }

  /// 上传单个图片文件
  Future<String?> _uploadSingleImage(String imagePath, SyncProvider provider) async {
    try {
      final absolutePath = await PathUtils.convertToAbsolutePath(imagePath);
      final file = File(absolutePath);
      if (!await file.exists()) {
        print('[HistorySync] 图片文件不存在: $imagePath');
        return null;
      }

      // 计算文件的MD5哈希值
      final bytes = await file.readAsBytes();
      final digest = md5.convert(bytes);
      final hash = digest.toString();

      // 生成对象键
      final objectKey = FileHashUtils.generateCloudObjectKey(imagePath, hash);
      print('[HistorySync] 生成图片对象键: $imagePath -> $objectKey');

      // 上传图片文件
       final uploadResult = await provider.uploadFile(
         absolutePath,
         objectKey,
       );

      if (uploadResult.success) {
        // // 创建图片索引信息
        // final indexData = {
        //   'originalPath': imagePath,
        //   'hash': hash,
        //   'uploadTime': DateTime.now().toIso8601String(),
        //   'size': bytes.length,
        // };

        // // 上传索引文件
        //  final indexKey = '$objectKey.index';
        //  final indexResult = await provider.uploadBytes(
        //    utf8.encode(jsonEncode(indexData)),
        //    indexKey,
        //    contentType: 'application/json',
        //  );
        //
        // if (indexResult.success) {
        //   print('[HistorySync] 图片及索引上传成功: $objectKey');
        // } else {
        //   print('[HistorySync] 图片索引上传失败: $indexKey');
        // }

        return objectKey;
      } else {
        print('[HistorySync] 图片上传失败: $objectKey, ${uploadResult.message}');
        return null;
      }
    } catch (e) {
      print('[HistorySync] 上传图片异常: $imagePath, 错误: $e');
      return null;
    }
  }

  Future<SyncResult> downloadData(SyncProvider provider, SyncDataType dataType) async {
    try {
      final dataTypeName = dataType.toString().split('.').last;
      final latestKey = '$dataTypeName-latest.json';
      final result = await provider.downloadBytes(latestKey);
      
      if (result.success && result.data != null) {
        final contentBytes = result.data!['content'] as List<int>;
        _logDebug('下载的数据长度: ${contentBytes.length} bytes');
        _logDebug('Content-Type: ${result.data!['contentType']}');
        
        try {
          final jsonString = utf8.decode(contentBytes);
          _logDebug('解码后的JSON字符串长度: ${jsonString.length}');
          final data = jsonDecode(jsonString) as Map<String, dynamic>;
          
          return SyncResult.success(
            message: '数据下载成功',
            data: data,
          );
        } catch (decodeError) {
          _logDebug('数据解码失败: $decodeError');
          _logDebug('原始数据前100字节: ${contentBytes.take(100).toList()}');
          return SyncResult.failure('数据解码失败: $decodeError');
        }
      } else {
        return SyncResult.failure('下载数据失败: ${result.message}');
      }
    } catch (e) {
      return SyncResult.failure('下载数据失败: $e');
    }
  }

  /// 日志输出
  void _logDebug(String message) {
    print('[historySync] $message');
  }

  /// 获取导航器上下文
  BuildContext? _getNavigatorContext() {
    return navigatorKey.currentContext;
  }

  /// 下载图片文件（使用已过滤的图片列表）
  Future<void> _downloadImageFiles(
    List<ImageFileInfo> imagesToDownload,
    SyncProvider provider,
    Map<String, String> imagePathToObjectKey,
    void Function(String step, {int? current, int? total})? onProgress,
  ) async {
    try {
      if (imagesToDownload.isEmpty) {
        print('[HistorySync] 没有需要下载的图片文件');
        return;
      }
      
      print('[HistorySync] 需要下载 ${imagesToDownload.length} 个图片文件');
      
      // 下载每个需要的图片文件
      int downloadedCount = 0;
      for (final imageInfo in imagesToDownload) {
        try {
          onProgress?.call('正在下载图片: ${imageInfo.filePath}', current: downloadedCount, total: imagesToDownload.length);
          print('[HistorySync] 正在下载图片: ${imageInfo.filePath}');
          
          final absolutedImagePath = await PathUtils.convertToAbsolutePath(imageInfo.filePath);
          final objectKey = imagePathToObjectKey[imageInfo.filePath];
          if (objectKey == null) {
            throw '未找到图片对象键: ${imageInfo.filePath}';
          }
          
          await _downloadSingleImageFromObjectKey(absolutedImagePath, objectKey, provider);
          downloadedCount++;
        } catch (e) {
          print('[HistorySync] 下载图片失败: ${imageInfo.filePath}, $e');
          downloadedCount++; // 即使失败也要增加计数
        }
      }
      print('[HistorySync] 图片下载完成');
    } catch (e) {
      print('[HistorySync] 下载图片过程中出错: $e');
    }
  }

  /// 从对象键下载单个图片文件
  Future<void> _downloadSingleImageFromObjectKey(
    String imagePath,
    String objectKey,
    SyncProvider provider,
  ) async {
    final file = File(imagePath);
    
    print('[HistorySync] 开始下载图片: $imagePath, 对象键: $objectKey');
    
    try {
      // 直接从对象存储下载图片
      final downloadResult = await provider.downloadBytes(objectKey);
      if (!downloadResult.success || downloadResult.data == null) {
        print('[HistorySync] 下载图片失败: $objectKey, ${downloadResult.message}');
        return;
      }
      
      final imageBytes = downloadResult.data!['content'] as List<int>;
      
      // 确保目录存在
      final directory = file.parent;
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      
      // 写入文件
      await file.writeAsBytes(imageBytes);
      print('[HistorySync] 图片下载成功: $imagePath (${imageBytes.length} bytes)');
    } catch (e) {
      print('[HistorySync] 下载图片异常: $imagePath, $e');
      rethrow;
    }
  }

}