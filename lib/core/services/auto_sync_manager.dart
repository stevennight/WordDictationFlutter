import 'dart:async';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:flutter/material.dart';

import 'sync_service.dart';
import 'history_sync_service.dart';
import 'wordbook_sync_service.dart';
import 'history_deletion_service.dart';
import '../../features/sync/widgets/sync_progress_dialog.dart';
import '../../main.dart';

/// 自动同步管理器
/// 负责管理基于时间间隔、应用启动时的自动同步
class AutoSyncManager with WidgetsBindingObserver {
  static SyncProgressDialog? _currentProgressDialog;
  static final AutoSyncManager _instance = AutoSyncManager._internal();

  factory AutoSyncManager() => _instance;

  AutoSyncManager._internal();

  final SyncService _syncService = SyncService();
  final HistorySyncService _historySyncService = HistorySyncService();
  final HistoryDeletionService _historyDeletionService = HistoryDeletionService();

  Timer? _syncTimer;
  Timer? _deletionTimer;
  bool _isInitialized = false;
  bool _isSyncing = false;

  /// 初始化自动同步管理器
  Future<void> initialize() async {
    if (_isInitialized) return;

    print('[AutoSyncManager] 初始化自动同步管理器');

    // 确保同步服务已初始化
    await _syncService.ensureInitialized();
    await _historySyncService.initialize();

    // 注册应用生命周期监听器
    WidgetsBinding.instance.addObserver(this);

    // 启动时执行一次自动同步
    _performStartupSync();

    // 启动定时同步
    _startPeriodicSync();

    // 启动定时硬删除
    _startPeriodicDeletion();

    _isInitialized = true;
    print('[AutoSyncManager] 自动同步管理器初始化完成');
  }

  /// 销毁自动同步管理器
  void dispose() {
    print('[AutoSyncManager] 销毁自动同步管理器');

    // 移除应用生命周期监听器
    WidgetsBinding.instance.removeObserver(this);

    // 停止定时器
    _syncTimer?.cancel();
    _syncTimer = null;
    
    _deletionTimer?.cancel();
    _deletionTimer = null;

    _isInitialized = false;
  }

  /// 应用生命周期状态变化
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    switch (state) {
      case AppLifecycleState.resumed:
        print('[AutoSyncManager] 应用恢复前台，检查是否需要同步');
        _checkAndPerformSync();
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        print('[AutoSyncManager] 应用进入后台/关闭，执行同步');
        _performShutdownSync();
        break;
      case AppLifecycleState.inactive:
        // 应用失去焦点，暂时不处理
        break;
      case AppLifecycleState.hidden:
        // 应用被隐藏，暂时不处理
        break;
    }
  }

  /// 启动时自动同步
  void _performStartupSync() {
    print('[AutoSyncManager] 执行启动时自动同步');
    _performStartupSyncWithUI();
  }

  /// 执行带UI的启动同步
  Future<void> _performStartupSyncWithUI() async {
    // 检查是否有启用自动同步的配置
    final configs = _syncService.configs
        .where((config) => config.enabled && config.autoSync)
        .toList();

    if (configs.isEmpty) {
      print('[AutoSyncManager] 没有启用自动同步的配置，跳过启动同步');
      return;
    }

    // 延迟一点时间确保UI已经准备好
    await Future.delayed(const Duration(milliseconds: 500));

    final context = navigatorKey.currentContext;
    if (context == null || !context.mounted) {
      print('[AutoSyncManager] 无法获取上下文，执行后台启动同步');
      _performAutoSync(reason: '应用启动');
      return;
    }

    // 使用与手动同步相同的进度对话框
    try {
      await showSyncProgressDialog<void>(
        context: context,
        title: '启动同步',
        syncFunction: (onProgress) async {
          await _performAutoSyncWithProgress(reason: '应用启动', onProgress: onProgress);
        },
      );
    } catch (e) {
      print('[AutoSyncManager] 启动同步失败: $e');
    }
  }

  /// 关闭时自动同步
  void _performShutdownSync() {
    print('[AutoSyncManager] 执行关闭时自动同步');
    _performAutoSync(reason: '应用关闭');
  }

  /// 启动定时同步
  void _startPeriodicSync() {
    _syncTimer?.cancel();

    // 获取最小的同步间隔
    final minInterval = _getMinSyncInterval();
    if (minInterval == null) {
      print('[AutoSyncManager] 没有启用自动同步的配置，不启动定时同步');
      return;
    }

    print('[AutoSyncManager] 启动定时同步，间隔: ${_formatDuration(minInterval)}');

    _syncTimer = Timer.periodic(minInterval, (timer) {
      print('[AutoSyncManager] 定时同步触发');
      _checkAndPerformSync();
    });
  }

  /// 获取最小的同步间隔
  Duration? _getMinSyncInterval() {
    final configs = _syncService.configs
        .where((config) => config.enabled && config.autoSync)
        .toList();

    if (configs.isEmpty) return null;

    Duration minInterval = configs.first.syncInterval;
    for (final config in configs.skip(1)) {
      if (config.syncInterval < minInterval) {
        minInterval = config.syncInterval;
      }
    }

    return minInterval;
  }

  /// 检查并执行同步
  void _checkAndPerformSync() {
    if (_isSyncing) {
      print('[AutoSyncManager] 同步正在进行中，跳过本次检查');
      return;
    }

    if (_needsSync()) {
      print('[AutoSyncManager] 检测到需要同步，执行定时同步');
      _performAutoSync(reason: '定时同步', withProgressDialog: false);
    } else {
      print('[AutoSyncManager] 暂时不需要同步');
    }
  }

  /// 检查是否需要同步
  bool _needsSync() {
    final now = DateTime.now();
    
    // 检查每个配置是否需要同步
    for (final config in _syncService.configs) {
      if (!config.enabled || !config.autoSync) continue;

      final lastSyncTime = config.lastSyncTime;
      if (lastSyncTime == null) {
        // 从未同步过，需要同步
        return true;
      }

      final timeSinceLastSync = now.difference(lastSyncTime);
      if (timeSinceLastSync >= config.syncInterval) {
        // 超过同步间隔，需要同步
        return true;
      }
    }
    
    return false;
  }

  /// 执行带进度回调的自动同步
  Future<void> _performAutoSyncWithProgress({
    required String reason,
    required void Function(String step, {int? current, int? total}) onProgress,
  }) async {
    if (_isSyncing) {
      print('[AutoSyncManager] 同步正在进行中，跳过 $reason');
      return;
    }

    _isSyncing = true;
    print('[AutoSyncManager] 开始执行自动同步 - $reason');

    try {
      final configs = _syncService.configs
          .where((config) => config.enabled && config.autoSync)
          .toList();

      if (configs.isEmpty) {
        print('[AutoSyncManager] 没有启用自动同步的配置');
        return;
      }

      final now = DateTime.now();

      for (final config in configs) {
        try {
          print('[AutoSyncManager] 同步配置: ${config.name}');
          onProgress('正在同步配置: ${config.name}');

          // 执行历史记录同步
          final historyResult = await _historySyncService.smartSyncHistory(
            config.id,
            onProgress: onProgress,
          );

          if (historyResult.success) {
            print('[AutoSyncManager] 配置 ${config.name} 历史记录同步成功');
          } else {
            print(
                '[AutoSyncManager] 配置 ${config.name} 历史记录同步失败: ${historyResult.message}');
          }

          // 可以在这里添加词书同步
          // final wordbookResult = await _wordbookSyncService.uploadWordbooks(config.id);
        } catch (e) {
          print('[AutoSyncManager] 配置 ${config.name} 同步失败: $e');
        }
      }

      onProgress('同步完成');
      print('[AutoSyncManager] 自动同步完成 - $reason');
    } catch (e) {
      print('[AutoSyncManager] 自动同步过程中发生错误: $e');
    } finally {
      _isSyncing = false;
    }
  }

  /// 执行自动同步（统一方法）
  Future<void> _performAutoSync({required String reason, bool withProgressDialog = false}) async {
    if (_isSyncing) {
      print('[AutoSyncManager] 同步正在进行中，跳过 $reason');
      return;
    }

    _isSyncing = true;
    print('[AutoSyncManager] 开始执行自动同步 - $reason');

    try {
      final configs = _syncService.configs
          .where((config) => config.enabled && config.autoSync)
          .toList();

      if (configs.isEmpty) {
        print('[AutoSyncManager] 没有启用自动同步的配置');
        return;
      }

      final now = DateTime.now();

      for (final config in configs) {
        try {
          // 对于定时同步，时间间隔检查已在 _checkAndPerformSync 中完成
          // 对于其他类型的同步（启动、关闭、手动），直接执行同步

          print('[AutoSyncManager] 同步配置: ${config.name}');

          // 执行历史记录同步
          final historyResult = await _historySyncService.smartSyncHistory(
            config.id,
            onProgress: (step, {current, total}) {
              print('[AutoSyncManager] 历史同步进度: $step');
              // 如果需要更新进度对话框
              if (withProgressDialog) {
                _updateProgressDialog(step, current: current, total: total);
              }
            },
          );

          if (historyResult.success) {
            print('[AutoSyncManager] 配置 ${config.name} 历史记录同步成功');
          } else {
            print(
                '[AutoSyncManager] 配置 ${config.name} 历史记录同步失败: ${historyResult.message}');
          }
        } catch (e) {
          print('[AutoSyncManager] 配置 ${config.name} 同步失败: $e');
        }
      }

      print('[AutoSyncManager] 自动同步完成 - $reason');
    } catch (e) {
      print('[AutoSyncManager] 自动同步过程中发生错误: $e');
    } finally {
      _isSyncing = false;
    }
  }

  /// 手动触发同步
  Future<void> triggerSync({String reason = '手动触发'}) async {
    print('[AutoSyncManager] 手动触发同步: $reason');
    await _performAutoSync(reason: reason);
  }

  /// 启动定时硬删除
  void _startPeriodicDeletion() {
    _deletionTimer?.cancel();

    // 每24小时执行一次硬删除检查
    const deletionInterval = Duration(hours: 24);
    print('[AutoSyncManager] 启动定时硬删除，间隔: ${_formatDuration(deletionInterval)}');

    _deletionTimer = Timer.periodic(deletionInterval, (timer) {
      print('[AutoSyncManager] 定时硬删除触发');
      _performPeriodicDeletion();
    });
  }

  /// 执行定时硬删除
   Future<void> _performPeriodicDeletion() async {
     try {
       print('[AutoSyncManager] 开始执行定时硬删除过期软删除记录');
       
       // 硬删除过期的软删除记录（不需要按配置分别处理，这是全局操作）
       await _historyDeletionService.hardDeleteExpiredSoftDeletedRecords();
       
       print('[AutoSyncManager] 定时硬删除完成');
     } catch (e) {
       print('[AutoSyncManager] 定时硬删除过程中发生错误: $e');
     }
   }

  /// 重新启动定时同步（配置更改后调用）
  void restartPeriodicSync() {
    print('[AutoSyncManager] 重新启动定时同步');
    _startPeriodicSync();
  }

  /// 重新启动定时硬删除（配置更改后调用）
  void restartPeriodicDeletion() {
    print('[AutoSyncManager] 重新启动定时硬删除');
    _startPeriodicDeletion();
  }

  /// 格式化时间间隔
  String _formatDuration(Duration duration) {
    if (duration.inDays > 0) {
      return '${duration.inDays}天';
    } else if (duration.inHours > 0) {
      return '${duration.inHours}小时';
    } else if (duration.inMinutes > 0) {
      return '${duration.inMinutes}分钟';
    } else {
      return '${duration.inSeconds}秒';
    }
  }

  /// 获取同步状态
  bool get isSyncing => _isSyncing;

  /// 获取是否已初始化
  bool get isInitialized => _isInitialized;

  /// 更新进度对话框
  void _updateProgressDialog(String step, {int? current, int? total}) {
    // 这里可以通过全局状态管理或者事件总线来更新进度对话框
    // 由于对话框是在另一个上下文中显示的，这里只是打印进度信息
    if (current != null && total != null) {
      print('[AutoSyncManager] 进度更新: $step ($current/$total)');
    } else {
      print('[AutoSyncManager] 进度更新: $step');
    }
  }
}
