import 'dart:convert';
import '../../shared/models/wordbook.dart';
import '../../shared/models/word.dart';
import 'wordbook_service.dart';

/// 同步数据类型枚举
enum SyncDataType {
  wordbooks,
  settings,
  history,
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
  SyncService._internal();

  final Map<String, SyncProvider> _providers = {};
  final List<SyncConfig> _configs = [];

  /// 注册同步提供商
  void registerProvider(String configId, SyncProvider provider) {
    _providers[configId] = provider;
  }

  /// 添加同步配置
  void addConfig(SyncConfig config) {
    _configs.removeWhere((c) => c.id == config.id);
    _configs.add(config);
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
  void removeConfig(String configId) {
    _configs.removeWhere((c) => c.id == configId);
    _providers.remove(configId);
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
            addConfig(updatedConfig);
          }
        }
        
        return result;
      } else {
        // 下载远程词书数据
        final result = await provider.downloadData(SyncDataType.wordbooks);
        
        if (result.success && result.data != null) {
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
            addConfig(updatedConfig);
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

  /// 导出所有词书数据（内部方法）
  Future<Map<String, dynamic>> _exportAllWordbooks() async {
    final WordbookService wordbookService = WordbookService();
    final allWordbooks = await wordbookService.getAllWordbooks();
    final List<Map<String, dynamic>> exportData = [];

    for (final wordbook in allWordbooks) {
      final words = await wordbookService.getWordbookWords(wordbook.id!);
      final wordbookMap = wordbook.toMap();
      wordbookMap['words'] = words.map((w) => w.toMap()).toList();
      exportData.add(wordbookMap);
    }

    return {
      'version': '1.0.0',
      'dataType': 'wordbooks',
      'createdAt': DateTime.now().toIso8601String(),
      'wordbooks': exportData,
    };
  }

  /// 导入词书数据（内部方法）
  Future<void> _importWordbooks(Map<String, dynamic> data) async {
    final WordbookService wordbookService = WordbookService();
    
    if (data['wordbooks'] == null || data['wordbooks'] is! List) {
      throw Exception('无效的同步数据格式');
    }

    final List<dynamic> wordbooksData = data['wordbooks'];
    
    for (final wordbookData in wordbooksData) {
      final List<Word> words = [];
      if (wordbookData['words'] != null && wordbookData['words'] is List) {
        final List<dynamic> wordsData = wordbookData['words'];
        for (final wordData in wordsData) {
          words.add(Word.fromMap(wordData));
        }
      }

      // 使用智能导入功能，如果词书已存在则更新，否则创建新的
      await wordbookService.importAndUpdateWordbook(
        name: wordbookData['name'] ?? '同步的词书',
        words: words,
        description: wordbookData['description'],
        originalFileName: 'sync-${DateTime.now().millisecondsSinceEpoch}.json',
      );
    }
  }
}