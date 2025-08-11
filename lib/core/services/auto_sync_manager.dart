import 'dart:async';
import 'dart:io';
import 'package:flutter/widgets.dart';

import 'sync_service.dart';
import 'history_sync_service.dart';
import 'wordbook_sync_service.dart';

/// 自动同步管理器
/// 负责管理基于时间间隔、应用启动和关闭时的自动同步
class AutoSyncManager with WidgetsBindingObserver {
  static final AutoSyncManager _instance = AutoSyncManager._internal();

  factory AutoSyncManager() => _instance;

  AutoSyncManager._internal();

  final SyncService _syncService = SyncService();
  final HistorySyncService _historySyncService = HistorySyncService();
  final WordbookSyncService _wordbookSyncService = WordbookSyncService();

  Timer? _syncTimer;
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
    _performAutoSync(reason: '应用启动');
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

    final now = DateTime.now();
    bool needSync = false;

    // 检查每个配置是否需要同步
    for (final config in _syncService.configs) {
      if (!config.enabled || !config.autoSync) continue;

      final lastSyncTime = config.lastSyncTime;
      if (lastSyncTime == null) {
        // 从未同步过，需要同步
        needSync = true;
        break;
      }

      final timeSinceLastSync = now.difference(lastSyncTime);
      if (timeSinceLastSync >= config.syncInterval) {
        // 超过同步间隔，需要同步
        needSync = true;
        break;
      }
    }

    if (needSync) {
      print('[AutoSyncManager] 检测到需要同步，执行定时同步');
      _performAutoSync(reason: '定时同步');
    } else {
      print('[AutoSyncManager] 暂时不需要同步');
    }
  }

  /// 执行自动同步
  Future<void> _performAutoSync({required String reason}) async {
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
          // 检查是否需要同步此配置
          final lastSyncTime = config.lastSyncTime;
          if (lastSyncTime != null && reason == '定时同步') {
            final timeSinceLastSync = now.difference(lastSyncTime);
            if (timeSinceLastSync < config.syncInterval) {
              print('[AutoSyncManager] 配置 ${config.name} 尚未到同步时间，跳过');
              continue;
            }
          }

          print('[AutoSyncManager] 同步配置: ${config.name}');

          // 执行历史记录同步
          final historyResult = await _historySyncService.smartSyncHistory(
            config.id,
            onProgress: (step, {current, total}) {
              print('[AutoSyncManager] 历史同步进度: $step');
            },
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

  /// 重新启动定时同步（配置更改后调用）
  void restartPeriodicSync() {
    print('[AutoSyncManager] 重新启动定时同步');
    _startPeriodicSync();
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
}
