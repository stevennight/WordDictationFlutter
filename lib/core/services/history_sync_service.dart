import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_word_dictation/shared/utils/path_utils.dart';
import 'package:path/path.dart' as path;
import 'package:path/path.dart' show dirname;

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
import 'config_service.dart';
import 'session_conflict_resolver.dart';
import 'file_index_manager.dart';
import 'session_file_service.dart';

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
  ConfigService? _configService;
  late HistoryFileSyncManager _historyFileSyncManager;
  late FileIndexManager _fileIndexManager;
  late String _deviceId;
  late Directory _appDocDir;
  late Directory _syncCacheDir;

  /// 初始化服务
  Future<void> initialize() async {
    // 初始化设备ID服务
    await _deviceIdService.initialize();
    _deviceId = await _deviceIdService.getDeviceId();
    
    // 初始化配置服务
    _configService = await ConfigService.getInstance();
    
    // Use unified path management
    _appDocDir = await PathUtils.getAppDirectory();
    
    
    _historyFileSyncManager = HistoryFileSyncManager();
    await _historyFileSyncManager.initialize();
    
    // 初始化文件索引管理器
    _fileIndexManager = FileIndexManager(_appDocDir.path);
    await _fileIndexManager.initialize();
  }

  /// 迁移旧版handwriting_cache中的笔迹图片为.session文件
  /// 对所有未删除的会话执行：若.session不存在，则根据数据库中的结果记录打包生成
  /// 可选：生成成功后删除旧的图片文件
  Future<Map<String, dynamic>> migrateLegacyCacheToSessionFiles({
    bool deleteLegacyImages = true,
    void Function(String step, {int? current, int? total})? onProgress,
  }) async {
    try {
      final sessions = await _dictationService.getAllSessions();
      int migrated = 0;
      int skipped = 0;
      int failed = 0;

      for (int i = 0; i < sessions.length; i++) {
        final s = sessions[i];
        onProgress?.call('检查会话: ${s.sessionId}', current: i, total: sessions.length);
        try {
          final sessionFilePath = await SessionFileService.getSessionFilePath(s.sessionId);
          final sessionFile = File(sessionFilePath);
          if (await sessionFile.exists()) {
            skipped++;
            continue;
          }

          // 获取结果并打包为session文件
          final results = await _dictationService.getSessionResults(s.sessionId);
          await SessionFileService.saveSessionFile(s, results);

          // 校验生成结果
          if (await sessionFile.exists()) {
            migrated++;

            if (deleteLegacyImages) {
              for (final r in results) {
                final paths = [r.originalImagePath, r.annotatedImagePath];
                for (final p in paths) {
                  if (p != null && p.isNotEmpty) {
                    try {
                      final abs = await PathUtils.convertToAbsolutePath(p);
                      final f = File(abs);
                      if (await f.exists()) {
                        await f.delete();
                      }
                    } catch (e) {
                      _logDebug('删除旧图片失败（$p）: $e');
                    }
                  }
                }
              }
            }
          } else {
            failed++;
            _logDebug('生成session文件失败: ${s.sessionId}');
          }
        } catch (e) {
          failed++;
          _logDebug('迁移会话失败: ${s.sessionId}, $e');
        }
      }

      return {
        'migrated': migrated,
        'skipped': skipped,
        'failed': failed,
        'total': sessions.length,
      };
    } catch (e) {
      return {
        'migrated': 0,
        'skipped': 0,
        'failed': 0,
        'total': 0,
        'error': '迁移失败: $e',
      };
    }
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
      
      // 清理远端数据中超过配置天数的软删除记录
      print('[HistorySync] 开始清理远端数据中的过期软删除记录');
      final retentionDays = await _configService!.getDeletedRecordsRetentionDays();
      final cutoffDate = DateTime.now().subtract(Duration(days: retentionDays));
      
      final filteredSessions = <SessionSyncData>[];
      int removedCount = 0;
      
      for (final session in syncData.sessions) {
        final sessionData = session.sessionData;
        final isDeleted = sessionData['deleted'] == 1;
        
        if (isDeleted) {
          // 检查删除时间
          final deletedAtStr = sessionData['deleted_at'] as String?;
          if (deletedAtStr != null) {
            final deletedAt = DateTime.parse(deletedAtStr);
            if (deletedAt.isBefore(cutoffDate)) {
              // 超过保留期限，不导入此记录
              print('[HistorySync] 跳过过期的软删除记录: ${session.sessionId}, 删除时间: $deletedAtStr');
              removedCount++;
              continue;
            }
          }
        }
        
        filteredSessions.add(session);
      }
      
      if (removedCount > 0) {
        print('[HistorySync] 已过滤掉 $removedCount 个过期的软删除记录');
        // 更新 syncData 中的 sessions
        final filteredSyncData = HistorySyncData(
          version: syncData.version,
          dataType: syncData.dataType,
          deviceId: syncData.deviceId,
          lastModified: syncData.lastModified,
          sessions: filteredSessions,
        );
        // 使用过滤后的数据继续处理
        final updatedData = filteredSyncData.toMap();
        data.clear();
        data.addAll(updatedData);
      }
      
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
      
      // 下载session文件
      final downloadResult = await _downloadSessionFiles(syncData, conflicts, provider, onProgress);
      final downloadedCount = downloadResult['downloaded'] as int? ?? 0;
      final totalToDownload = downloadResult['total'] as int? ?? 0;
      
      print('[HistorySync] 导入历史记录：找到 ${syncData.sessions.length} 个会话');
      print('[HistorySync] 导入历史记录：已经下载 $downloadedCount/$totalToDownload 个session文件');
      
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
        message: '成功导入 $importedSessions 个会话，$importedResults 个结果，已下载 $downloadedCount 个session文件',
        data: {
          'importedSessions': importedSessions,
          'importedResults': importedResults,
          'downloadedSessions': downloadedCount,
          'totalSessionsToDownload': totalToDownload,
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

      // 0. 硬删除过期的软删除记录
      onProgress?.call('正在清理过期的删除记录...');
      print('[HistorySyncService] 第零步：硬删除过期的软删除记录');
      try {
        await _deletionService.hardDeleteExpiredSoftDeletedRecords();
        print('[HistorySyncService] 过期软删除记录清理完成');
      } catch (e) {
        print('[HistorySyncService] 清理过期软删除记录时出错: $e');
        // 不中断同步流程，继续执行
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
      
      // 2.5. 检测设备离线时间，如果超过配置天数则提示用户选择同步策略
      final config = syncService.getConfig(configId);
      if (config?.lastSyncTime != null) {
        final retentionDays = await _configService!.getDeletedRecordsRetentionDays();
        final daysSinceLastSync = DateTime.now().difference(config!.lastSyncTime!).inDays;
        if (daysSinceLastSync > retentionDays) {
          print('[HistorySyncService] 设备离线超过${retentionDays}天 ($daysSinceLastSync天)，需要用户确认同步策略');
          
          // 显示用户确认对话框
           final shouldOverwrite = await _showOfflineDeviceDialog(daysSinceLastSync, retentionDays);
          if (shouldOverwrite == null) {
            // 用户取消同步
            return SyncResult.failure('用户取消了同步操作');
          } else if (shouldOverwrite) {
            // 用户选择用远端数据覆盖本地数据
            print('[HistorySyncService] 用户选择用远端数据覆盖本地数据');
            onProgress?.call('正在用云端数据覆盖本地数据...');
            
            // 清空本地数据并导入远端数据
            if (remoteSessions.isNotEmpty) {
              await _clearLocalDataAndImportRemote(remoteHistoryData, provider, onImportComplete, onProgress);
            }
            
            // 更新同步时间
            await syncService.updateConfigLastSyncTime(configId);

            // 同步结束后清理本地索引中不存在的文件，并上传最终索引到远端
            try {
              onProgress?.call('正在清理本地索引并上传到云端...');
              await _fileIndexManager.cleanupLocalIndex(_appDocDir.path);
              await _fileIndexManager.uploadIndexToRemote(provider);
              print('[HistorySyncService] 同步后索引清理并上传完成');
            } catch (e) {
              print('[HistorySyncService] 同步后索引清理/上传失败: $e');
            }

            return SyncResult.success(message: '已用云端数据覆盖本地数据');
          }
          // 如果用户选择继续正常同步，则继续执行下面的双向合并逻辑
        }
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
        // 清理旧的备份文件
        onProgress?.call('正在清理旧的备份文件...');
        print('[HistorySyncService] 第五步：清理旧的备份文件');
        final config = syncService.getConfig(configId);
        final retentionCount = config?.retentionCount ?? 10;
        final cleanupResult = await cleanupOldBackups(provider, SyncDataType.history, retentionCount);
        if (cleanupResult.success) {
          print('[HistorySyncService] 备份文件清理成功: ${cleanupResult.message}');
        } else {
          print('[HistorySyncService] 备份文件清理失败: ${cleanupResult.message}');
        }
        
        // 更新配置中的同步时间
        await syncService.updateConfigLastSyncTime(configId);

        // 同步结束后清理本地索引中不存在的文件，并上传最终索引到远端
        try {
          onProgress?.call('正在清理本地索引并上传到云端...');
          await _fileIndexManager.cleanupLocalIndex(_appDocDir.path);
          await _fileIndexManager.uploadIndexToRemote(provider);
          print('[HistorySyncService] 同步后索引清理并上传完成');
        } catch (e) {
          print('[HistorySyncService] 同步后索引清理/上传失败: $e');
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
  
  /// 上传历史记录数据（上传JSON与 .session 文件）
  Future<SyncResult> _uploadHistoryData(SyncProvider provider, List<dynamic> remoteSessions, Map<String, dynamic> mergeHistoryData, void Function(String step, {int? current, int? total})? onProgress) async {
    try {
      print('[HistorySync] 开始上传历史记录数据');

      // 上传合并后的JSON数据
      const dataType = SyncDataType.history;
      _logDebug('开始上传数据，类型: $dataType');

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final dataTypeName = dataType.toString().split('.').last;
      final objectKey = "backup/$dataTypeName-$timestamp.json";
      final latestKey = "$dataTypeName-latest.json";
      final jsonData = jsonEncode(mergeHistoryData);
      final bytes = utf8.encode(jsonData);

      _logDebug('上传JSON数据，大小: ${bytes.length} bytes');

      final uploadResult = await provider.uploadBytes(bytes, objectKey);
      if (!uploadResult.success) {
        _logDebug('上传主文件失败: ${uploadResult.message}');
        return uploadResult;
      }

      final latestResult = await provider.uploadBytes(bytes, latestKey);
      if (!latestResult.success) {
        _logDebug('上传latest文件失败: ${latestResult.message}');
        return SyncResult.failure('上传latest文件失败: ${latestResult.message}');
      }

      _logDebug('历史记录数据上传完成');

      // 上传 .session 文件（仅未删除的会话），并按文件索引去重
      final sessions = mergeHistoryData['sessions'] as List<dynamic>? ?? [];
      final sessionsToUpload = <String>[]; // sessionId 列表
      for (final session in sessions) {
        final sessionMap = session as Map<String, dynamic>;
        final sessionData = sessionMap['sessionData'] as Map<String, dynamic>;
        if ((sessionData['deleted'] ?? 0) == 0) {
          sessionsToUpload.add(sessionData['session_id'] as String);
        }
      }

      // 更新本地索引中对应的 session 文件项
      final sessionRelativePaths = <String>[];
      for (final sessionId in sessionsToUpload) {
        final relativePath = 'sessions/$sessionId.session';
        final absolutePath = await SessionFileService.getSessionFilePath(sessionId);
        final file = File(absolutePath);
        if (!await file.exists()) {
          // 如果缺少，尝试重建
          try {
            final s = await _dictationService.getSession(sessionId);
            if (s != null) {
              final results = await _dictationService.getSessionResults(sessionId);
              await SessionFileService.saveSessionFile(s, results);
            }
          } catch (e) {
            _logDebug('为上传重建session文件失败: $e');
          }
        }
        if (await file.exists()) {
          await _fileIndexManager.updateLocalFileIndex(relativePath, absolutePath);
          sessionRelativePaths.add(relativePath);
        } else {
          _logDebug('跳过索引与上传：本地缺少session文件 $sessionId');
        }
      }
      await _fileIndexManager.saveLocalIndex();

      // 下载远端索引并比较，筛选需要上传的 session 文件
      final remoteIndex = await _fileIndexManager.downloadRemoteIndex(provider);
      final compare = _fileIndexManager.compareIndexes(remoteIndex);
      final toUploadRelative = compare['upload']!
          .where((p) => p.startsWith('sessions/'))
          .where((p) => sessionRelativePaths.contains(p))
          .toList();

      int uploadedCount = 0;
      for (int i = 0; i < toUploadRelative.length; i++) {
        final relativePath = toUploadRelative[i];
        final sessionId = relativePath.split('/').last.replaceAll('.session', '');
        onProgress?.call('正在上传会话文件: $sessionId', current: uploadedCount, total: toUploadRelative.length);

        final absolutePath = await SessionFileService.getSessionFilePath(sessionId);
        final r = await provider.uploadFile(absolutePath, relativePath);
        if (r.success) {
          uploadedCount++;
        } else {
          _logDebug('上传session文件失败: ${r.message}');
        }
      }

      // 上传更新后的索引到远端（包含会话文件的变更）
      await _fileIndexManager.uploadIndexToRemote(provider);

      return SyncResult.success(
        message: '历史记录上传成功，已上传 $uploadedCount 个会话文件',
        data: {
          'objectKey': objectKey,
          'latestKey': latestKey,
          'uploadedSessions': uploadedCount,
          'totalSessions': toUploadRelative.length,
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
    print('[HistorySync] $message');
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

 /// 下载session文件（按会话整体下载 .session 文件）
 Future<Map<String, dynamic>> _downloadSessionFiles(
   HistorySyncData syncData,
   List<SessionConflict> conflicts,
   SyncProvider? provider,
   void Function(String step, {int? current, int? total})? onProgress,
 ) async {
   int downloaded = 0;

   // 若未提供provider，沿用旧逻辑：只补齐缺失的本地文件
   if (provider == null) {
     int total = 0;
     for (final sessionSync in syncData.sessions) {
       final conflict = conflicts.where((c) => c.sessionId == sessionSync.sessionId).firstOrNull;
       DictationSession? finalSession;
       if (conflict != null) {
         finalSession = _conflictResolver.getSessionToApply(conflict);
       } else {
         finalSession = DictationSession.fromMap(sessionSync.sessionData);
       }
       if (finalSession != null && !finalSession.deleted) {
         total++;
         // 未提供provider，无法执行下载，这里仅统计总数
       }
     }
     return {'downloaded': 0, 'total': total};
   }

   // 使用文件索引做去重：按远端索引比较，下载差异的 .session 文件
   // 先将已有的本地 .session 文件更新到本地索引
   for (final sessionSync in syncData.sessions) {
     final conflict = conflicts.where((c) => c.sessionId == sessionSync.sessionId).firstOrNull;
     final DictationSession finalSession = (conflict != null)
         ? (_conflictResolver.getSessionToApply(conflict) ?? DictationSession.fromMap(sessionSync.sessionData))
         : DictationSession.fromMap(sessionSync.sessionData);
     if (!finalSession.deleted) {
       final sessionId = finalSession.sessionId;
       final relativePath = 'sessions/$sessionId.session';
       final absolutePath = await SessionFileService.getSessionFilePath(sessionId);
       final file = File(absolutePath);
       if (await file.exists()) {
         await _fileIndexManager.updateLocalFileIndex(relativePath, absolutePath);
       } else {
         // 缺失的不用加入索引，后续由比较结果决定是否下载
       }
     }
   }
   await _fileIndexManager.saveLocalIndex();

   // 下载远端索引并比较
   final remoteIndex = await _fileIndexManager.downloadRemoteIndex(provider);
   final compare = _fileIndexManager.compareIndexes(remoteIndex);
   final toDownloadRelative = compare['download']!
       .where((p) => p.startsWith('sessions/'))
       .toList();

   final total = toDownloadRelative.length;
   for (int i = 0; i < toDownloadRelative.length; i++) {
     final relativePath = toDownloadRelative[i];
     final sessionId = relativePath.split('/').last.replaceAll('.session', '');
     final absolutePath = await SessionFileService.getSessionFilePath(sessionId);
     onProgress?.call('正在下载会话文件: $sessionId', current: i, total: total);
     final result = await provider.downloadBytes(relativePath);
     if (result.success && result.data != null) {
       final bytes = result.data!['data'] as List<int>;
       final file = File(absolutePath);
       await file.parent.create(recursive: true);
       await file.writeAsBytes(bytes);
       await _fileIndexManager.updateLocalFileIndex(relativePath, absolutePath);
       downloaded++;
     } else {
       _logDebug('下载session文件失败: $relativePath, ${result.message}');
     }
   }

   // 下载完成后同步索引
   await _fileIndexManager.saveLocalIndex();

   return {
     'downloaded': downloaded,
     'total': total,
   };
 }

  /// 扫描并更新handwriting_cache目录的索引
  Future<void> _scanAndUpdateHandwritingCacheIndex() async {
    try {
      // 直接扫描应用根目录下的userdata/temp/handwriting_cache目录
      final appDir = await PathUtils.getAppDirectory();
      final handwritingCacheDir = Directory(path.join(appDir.path, 'userdata/temp/handwriting_cache'));
      
      if (!await handwritingCacheDir.exists()) {
        print('[HistorySync] handwriting_cache目录不存在，跳过扫描');
         return;
       }
       
       print('[HistorySync] 开始扫描handwriting_cache目录: ${handwritingCacheDir.path}');
       
       // 先清理本地索引中已不存在的文件记录，避免残留老路径如 "handwriting_cache/..."
       await _fileIndexManager.cleanupLocalIndex(appDir.path);
       print('[HistorySync] 已清理不存在的文件索引记录');
       
       final files = <String>[];
       await for (final entity in handwritingCacheDir.list(recursive: true)) {
         if (entity is File) {
           // 使用PathUtils确保路径格式与数据库一致（正斜杠格式）
           final relativePath = await PathUtils.convertToRelativePath(entity.path);
           files.add(relativePath);
         }
       }
       
       print('[HistorySync] 找到 ${files.length} 个文件需要更新索引');
       
       if (files.isNotEmpty) {
         // 批量更新本地索引，使用应用根目录作为基准路径
         await _fileIndexManager.batchUpdateLocalIndex(files, appDir.path);
         print('[HistorySync] handwriting_cache目录索引更新完成');
       }
    } catch (e) {
      print('[HistorySync] 扫描handwriting_cache目录失败: $e');
    }
  }
  
  /// 合并远端索引与本地索引
  Future<void> _mergeRemoteIndexWithLocal(FileIndex remoteIndex) async {
    try {
      print('[HistorySync] 开始合并远端索引与本地索引');
       
       final localIndex = _fileIndexManager.localIndex;
       if (localIndex == null) {
         print('[HistorySync] 本地索引为空，直接使用远端索引');
         return;
       }
      
      var mergedCount = 0;
      
      // 将远端索引中的文件信息合并到本地索引
      for (final entry in remoteIndex.files.entries) {
        final relativePath = entry.key;
        final remoteItem = entry.value;
        final localItem = localIndex.files[relativePath];
        
        // 如果本地没有这个文件，或者远端文件更新，则添加到本地索引
        if (localItem == null || remoteItem.lastModified.isAfter(localItem.lastModified)) {
          localIndex.updateFile(remoteItem);
          mergedCount++;
        }
      }
      
      if (mergedCount > 0) {
        // 更新本地索引的时间戳
        final now = DateTime.now();
        final mergedIndex = localIndex.copyWith(
          updatedAt: now,
        );
        
        // 保存合并后的索引
          await _fileIndexManager.saveLocalIndex();
          print('[HistorySync] 索引合并完成，合并了 $mergedCount 个文件');
      } else {
         print('[HistorySync] 无需合并，本地索引已是最新');
       }
     } catch (e) {
       print('[HistorySync] 合并远端索引失败: $e');
    }
  }

  /// 清理旧的备份文件，保留指定数量的最新备份
  /// [provider] 同步提供者
  /// [dataType] 数据类型
  /// [retentionCount] 保留的备份数量
  Future<SyncResult> cleanupOldBackups(SyncProvider provider, SyncDataType dataType, int retentionCount) async {
    try {
      final dataTypeName = dataType.toString().split('.').last;
      print('[HistorySync] 开始清理旧的 $dataTypeName 备份文件，保留 $retentionCount 份');
      
      // 列出backup目录下的所有备份文件
      final listResult = await provider.listFiles('backup', recursive: false);
      if (!listResult.success) {
        return SyncResult.failure('获取文件列表失败: ${listResult.message}');
      }
      
      final files = listResult.data!['files'] as List<Map<String, dynamic>>;
      
      // 过滤出指定类型的带时间戳的备份文件
      final regex = RegExp(r'^' + dataTypeName + r'-(\d+)\.json$');
      final backupFiles = files.where((file) {
        final relativePath = file['relativePath'] as String;
        return regex.hasMatch(relativePath);
      }).toList();
      
      print('[HistorySync] 找到 ${backupFiles.length} 个 $dataTypeName 备份文件');
      
      if (backupFiles.length <= retentionCount) {
        print('[HistorySync] 备份文件数量不超过保留数量，无需清理');
        return SyncResult.success(message: '无需清理备份文件');
      }
      
      // 按时间戳排序（从新到旧）
      backupFiles.sort((a, b) {
        final aPath = a['relativePath'] as String;
        final bPath = b['relativePath'] as String;
        final aTimestamp = int.parse(RegExp(r'\w+-(\d+)\.json$').firstMatch(aPath)!.group(1)!);
        final bTimestamp = int.parse(RegExp(r'\w+-(\d+)\.json$').firstMatch(bPath)!.group(1)!);
        return bTimestamp.compareTo(aTimestamp); // 降序排列
      });
      
      // 删除多余的旧备份文件
      final filesToDelete = backupFiles.skip(retentionCount).toList();
      print('[HistorySync] 需要删除 ${filesToDelete.length} 个旧备份文件');
      
      int deletedCount = 0;
      for (final file in filesToDelete) {
        final relativePath = file['relativePath'] as String;
        try {
          // 构建完整的备份文件路径
          final backupFilePath = 'backup/$relativePath';
          final deleteResult = await provider.deleteFile(backupFilePath);
          if (deleteResult.success) {
            deletedCount++;
            print('[HistorySync] 已删除旧备份文件: $relativePath');
          } else {
            print('[HistorySync] 删除备份文件失败: $relativePath, ${deleteResult.message}');
          }
        } catch (e) {
          print('[HistorySync] 删除备份文件异常: $relativePath, $e');
        }
      }
      
      print('[HistorySync] 备份文件清理完成，删除了 $deletedCount 个文件');
      return SyncResult.success(message: '清理完成，删除了 $deletedCount 个旧备份文件');
    } catch (e) {
      print('[HistorySync] 清理备份文件时发生错误: $e');
      return SyncResult.failure('清理备份文件失败: $e');
    }
  }

  /// 显示离线设备确认对话框
  Future<bool?> _showOfflineDeviceDialog(int daysSinceLastSync, int retentionDays) async {
    final context = _getNavigatorContext();
    if (context == null) {
      print('[HistorySync] 无法获取 BuildContext，默认选择继续正常同步');
      return false; // 默认选择继续正常同步
    }

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('设备离线时间过长'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('您的设备已离线 $daysSinceLastSync 天，超过了$retentionDays天的安全阈值。'),
              const SizedBox(height: 16),
              const Text('为了避免数据冲突，建议选择以下操作之一：'),
              const SizedBox(height: 12),
              const Text('• 用云端数据覆盖本地数据（推荐）'),
              const Text('• 继续正常同步（可能产生冲突）'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('取消同步'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('继续正常同步'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('用云端数据覆盖'),
            ),
          ],
        );
      },
    );
  }

  /// 清空本地数据并导入远端数据
  Future<void> _clearLocalDataAndImportRemote(
    Map<String, dynamic> remoteHistoryData,
    SyncProvider? provider,
    VoidCallback? onImportComplete,
    void Function(String step, {int? current, int? total})? onProgress,
  ) async {
    try {
      // 1. 清空本地所有历史记录数据
      onProgress?.call('正在清空本地数据...');
      print('[HistorySync] 开始清空本地历史记录数据');
      
      final db = await _dbHelper.database;
      await db.transaction((txn) async {
        // 删除所有会话结果
        await txn.delete('dictation_results');
        // 删除所有会话
        await txn.delete('dictation_sessions');
      });
      
      print('[HistorySync] 本地历史记录数据清空完成');
      
      // 2. 导入远端数据
      onProgress?.call('正在导入云端数据...');
      print('[HistorySync] 开始导入远端数据');
      
      final importResult = await importHistoryData(
        remoteHistoryData,
        provider,
        onImportComplete,
        onProgress,
      );
      
      if (!importResult.success) {
        throw Exception('导入远端数据失败: ${importResult.message}');
      }
      
      print('[HistorySync] 远端数据导入完成');
    } catch (e) {
      print('[HistorySync] 清空本地数据并导入远端数据时发生错误: $e');
      rethrow;
    }
  }

}