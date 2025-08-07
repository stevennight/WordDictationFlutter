import 'dart:convert';
import '../../shared/models/wordbook.dart';
import '../../shared/models/word.dart';
import '../../shared/models/unit.dart';
import 'local_config_service.dart';
import 'json_data_service.dart';
import 'import_data_service.dart';
import 'object_storage_sync_provider.dart';
import 'history_sync_service.dart';

/// 同步数据类型枚举
enum SyncDataType {
  wordbooks,
  settings,
  history,
  historyImages, // 历史记录图片文件
  // 预留其他数据类型
}

/// 同步操作结果
class SyncResult {
  final bool success;
  final String? message;
  final Map<String, dynamic>? data;
  final DateTime timestamp;

  SyncResult({
    required this.success,
    this.message,
    this.data,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  SyncResult.success({String? message, Map<String, dynamic>? data})
      : this(success: true, message: message, data: data);

  SyncResult.failure(String message)
      : this(success: false, message: message);
}

/// 同步配置
class SyncConfig {
  final String id;
  final String name;
  final SyncProviderType providerType;
  final Map<String, dynamic> settings;
  final bool autoSync;
  final Duration syncInterval;
  final DateTime? lastSyncTime;
  final bool enabled;

  SyncConfig({
    required this.id,
    required this.name,
    required this.providerType,
    required this.settings,
    this.autoSync = false,
    this.syncInterval = const Duration(hours: 1),
    this.lastSyncTime,
    this.enabled = true,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'providerType': providerType.toString(),
      'settings': jsonEncode(settings),
      'autoSync': autoSync,
      'syncInterval': syncInterval.inMilliseconds,
      'lastSyncTime': lastSyncTime?.millisecondsSinceEpoch,
      'enabled': enabled,
    };
  }

  factory SyncConfig.fromMap(Map<String, dynamic> map) {
    return SyncConfig(
      id: map['id'],
      name: map['name'],
      providerType: SyncProviderType.values.firstWhere(
        (e) => e.toString() == map['providerType'],
      ),
      settings: jsonDecode(map['settings']),
      autoSync: map['autoSync'] ?? false,
      syncInterval: Duration(milliseconds: map['syncInterval'] ?? 3600000),
      lastSyncTime: map['lastSyncTime'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['lastSyncTime'])
          : null,
      enabled: map['enabled'] ?? true,
    );
  }
}

/// 同步提供商类型
enum SyncProviderType {
  objectStorage,
  webdav,
  ftp,
  // 预留其他同步方式
}

/// 抽象同步提供商接口
abstract class SyncProvider {
  final SyncConfig config;

  SyncProvider(this.config);

  /// 获取提供商类型
  SyncProviderType get providerType;

  /// 测试连接
  Future<SyncResult> testConnection();

  /// 上传数据
  Future<SyncResult> uploadData(SyncDataType dataType, Map<String, dynamic> data);

  /// 下载数据
  Future<SyncResult> downloadData(SyncDataType dataType);

  /// 删除远程数据
  Future<SyncResult> deleteData(SyncDataType dataType);

  /// 获取远程数据信息（如最后修改时间等）
  Future<SyncResult> getDataInfo(SyncDataType dataType);

  /// 列出所有可用的数据文件
  Future<SyncResult> listDataFiles();
}

/// 同步服务主类
class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal() {
    _loadConfigs();
  }

  final Map<String, SyncProvider> _providers = {};
  final List<SyncConfig> _configs = [];
  bool _initialized = false;

  /// 注册同步提供商
  void registerProvider(String configId, SyncProvider provider) {
    _providers[configId] = provider;
  }

  /// 添加同步配置
  Future<void> addConfig(SyncConfig config) async {
    _configs.removeWhere((c) => c.id == config.id);
    _configs.add(config);
    
    // 自动注册提供商
    _registerProviderForConfig(config);
    
    await _saveConfigs();
  }

  /// 获取所有配置
  List<SyncConfig> get configs => List.unmodifiable(_configs);

  /// 获取指定配置
  SyncConfig? getConfig(String configId) {
    try {
      return _configs.firstWhere((c) => c.id == configId);
    } catch (e) {
      return null;
    }
  }

  /// 删除配置
  Future<void> removeConfig(String configId) async {
    _configs.removeWhere((c) => c.id == configId);
    _providers.remove(configId);
    await _saveConfigs();
  }

  /// 同步历史记录数据
  Future<SyncResult> syncHistory(String configId, {
    bool upload = true,
    DateTime? since,
    bool includeImages = true,
  }) async {
    final provider = _providers[configId];
    if (provider == null) {
      return SyncResult.failure('同步配置不存在');
    }

    try {
      final historySyncService = HistorySyncService();
      await historySyncService.initialize();

      if (upload) {
        // 上传历史记录数据
        final lastSyncTime = since ?? await historySyncService.getLastSyncTime(configId);
        final historyData = await historySyncService.exportHistoryData(since: lastSyncTime);
        
        // 检查是否为空数据
        final sessions = historyData['sessions'] as List<dynamic>;
        if (sessions.isEmpty) {
          return SyncResult.failure('没有需要同步的历史记录数据');
        }
        
        final result = await provider.uploadData(SyncDataType.history, historyData);
        
        if (result.success) {
          // 更新最后同步时间
          await historySyncService.saveLastSyncTime(configId, DateTime.now());
          
          // 更新配置中的同步时间
          final config = getConfig(configId);
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
            await addConfig(updatedConfig);
          }
        }
        
        return result;
      } else {
        // 下载历史记录数据
        final result = await provider.downloadData(SyncDataType.history);
        
        if (result.success && result.data != null) {
          final importResult = await historySyncService.importHistoryData(result.data!);
          
          if (importResult.success) {
            // 更新最后同步时间
            await historySyncService.saveLastSyncTime(configId, DateTime.now());
            
            // 更新配置中的同步时间
            final config = getConfig(configId);
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
              await addConfig(updatedConfig);
            }
            
            return SyncResult.success(message: '历史记录同步成功: ${importResult.message}');
          } else {
            return importResult;
          }
        }
        
        return result;
      }
    } catch (e) {
      return SyncResult.failure('历史记录同步失败: $e');
    }
  }

  /// 同步词书数据
  Future<SyncResult> syncWordbooks(String configId, {bool upload = true}) async {
    final provider = _providers[configId];
    if (provider == null) {
      return SyncResult.failure('同步配置不存在');
    }

    try {
      if (upload) {
        // 上传本地词书数据
        final wordbooksData = await _exportAllWordbooks();
        
        // 检查是否为空数据
        if (!_isValidDataForUpload(wordbooksData)) {
          return SyncResult.failure('本地数据为空或无效，为避免覆盖远端数据，请先添加词书后再同步');
        }
        
        final result = await provider.uploadData(SyncDataType.wordbooks, wordbooksData);
        
        if (result.success) {
          // 更新最后同步时间
          final config = getConfig(configId);
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
            await addConfig(updatedConfig);
          }
        }
        
        return result;
      } else {
        // 下载远程词书数据
        final result = await provider.downloadData(SyncDataType.wordbooks);
        
        if (result.success && result.data != null) {
          // 检查下载的数据是否有效
          if (!_isValidDataForImport(result.data!)) {
            return SyncResult.failure('远端数据为空或格式无效');
          }
          
          await _importWordbooks(result.data!);
          
          // 更新最后同步时间
          final config = getConfig(configId);
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
            await addConfig(updatedConfig);
          }
          
          return SyncResult.success(message: '词书数据同步成功');
        }
        
        return result;
      }
    } catch (e) {
      return SyncResult.failure('同步失败: $e');
    }
  }

  /// 测试同步配置
  Future<SyncResult> testConfig(String configId) async {
    final provider = _providers[configId];
    if (provider == null) {
      return SyncResult.failure('同步配置不存在');
    }

    return await provider.testConnection();
  }

  /// 加载同步配置
  Future<void> _loadConfigs() async {
    if (_initialized) return;
    
    try {
       final localConfig = await LocalConfigService.getInstance();
       final configsData = await localConfig.getSetting<List<dynamic>>('sync_configs') ?? [];
      
      _configs.clear();
      _providers.clear(); // 清空现有提供商
      
      for (final configData in configsData) {
        if (configData is Map<String, dynamic>) {
          try {
            final config = SyncConfig.fromMap(configData);
            _configs.add(config);
            
            // 自动注册提供商
            _registerProviderForConfig(config);
          } catch (e) {
            print('Failed to load sync config: $e');
          }
        }
      }
      
      _initialized = true;
      print('Loaded ${_configs.length} sync configs and registered providers');
    } catch (e) {
      print('Failed to load sync configs: $e');
      _initialized = true;
    }
  }
  
  /// 为配置自动注册提供商
  void _registerProviderForConfig(SyncConfig config) {
    try {
      if (config.providerType == SyncProviderType.objectStorage) {
        final provider = ObjectStorageSyncProvider(config);
        _providers[config.id] = provider;
        print('Registered ObjectStorage provider for config: ${config.name}');
      }
      // 未来可以在这里添加其他类型的提供商
    } catch (e) {
      print('Failed to register provider for config ${config.name}: $e');
    }
  }

  /// 保存同步配置
  Future<void> _saveConfigs() async {
    try {
       final localConfig = await LocalConfigService.getInstance();
       final configsData = _configs.map((config) => config.toMap()).toList();
      await localConfig.setSetting('sync_configs', configsData);
      print('Saved ${_configs.length} sync configs');
    } catch (e) {
      print('Failed to save sync configs: $e');
    }
  }

  /// 确保配置已加载
  Future<void> ensureInitialized() async {
    if (!_initialized) {
      await _loadConfigs();
    }
  }

  /// 导出所有词书数据（内部方法）
  Future<Map<String, dynamic>> _exportAllWordbooks() async {
    final jsonDataService = JsonDataService();
    return await jsonDataService.exportAllWordbooks();
  }

  /// 验证上传数据是否有效
  bool _isValidDataForUpload(Map<String, dynamic> data) {
    // 检查基本格式
    if (data['wordbooks'] == null || data['wordbooks'] is! List) {
      return false;
    }
    
    final List<dynamic> wordbooks = data['wordbooks'];
    
    // 检查是否有词书
    if (wordbooks.isEmpty) {
      return false;
    }
    
    // 检查是否至少有一个词书包含单词
    bool hasValidWordbook = false;
    for (final wordbook in wordbooks) {
      if (wordbook is Map<String, dynamic> && 
          wordbook['words'] is List && 
          (wordbook['words'] as List).isNotEmpty) {
        hasValidWordbook = true;
        break;
      }
    }
    
    return hasValidWordbook;
  }
  
  /// 验证导入数据是否有效
  bool _isValidDataForImport(Map<String, dynamic> data) {
    // 检查基本格式
    if (data['wordbooks'] == null || data['wordbooks'] is! List) {
      return false;
    }
    
    final List<dynamic> wordbooks = data['wordbooks'];
    
    // 允许空词书列表（用户可能想清空本地数据）
    // 但需要确保格式正确
    for (final wordbook in wordbooks) {
      if (wordbook is! Map<String, dynamic>) {
        return false;
      }
      
      // 检查词书必需字段
      if (wordbook['name'] == null || wordbook['name'] is! String) {
        return false;
      }
    }
    
    return true;
  }

  /// 导入词书数据（内部方法）
  Future<void> _importWordbooks(Map<String, dynamic> data) async {
    final importDataService = ImportDataService();
    final result = await importDataService.importFromJsonData(data);
    if (!result.success) {
      throw Exception(result.message);
    }
  }
}