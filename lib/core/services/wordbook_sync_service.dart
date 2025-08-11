import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import 'sync_service.dart';
import 'import_data_service.dart';
import 'json_data_service.dart';

/// 单词本同步服务
class WordbookSyncService {
  static final WordbookSyncService _instance = WordbookSyncService._internal();
  static WordbookSyncService get instance => _instance;
  factory WordbookSyncService() => _instance;
  WordbookSyncService._internal();

  Future<SyncResult> syncWordbooks(String configId, {bool upload = true}) async {
    final syncService = SyncService();
    final provider = syncService.getProvider(configId);
    if (provider == null) {
      return SyncResult.failure('同步配置不存在');
    }

    SyncResult result;
    try {
      if (upload) {
        // 上传本地词书数据
        final wordbooksData = await _exportAllWordbooks();
        
        // 检查是否为空数据
        if (!_isValidDataForUpload(wordbooksData)) {
          return SyncResult.failure('本地数据为空或无效，为避免覆盖远端数据，请先添加词书后再同步');
        }
        
        result = await uploadData(provider, SyncDataType.wordbooks, wordbooksData, null);
      } else {
        // 下载远程词书数据
        result = await downloadData(provider, SyncDataType.wordbooks);
        
        if (result.success && result.data != null) {
          // 检查下载的数据是否有效
          if (!_isValidDataForImport(result.data!)) {
            return SyncResult.failure('远端数据为空或格式无效');
          }
          
          await _importWordbooks(result.data!);
          
          return SyncResult.success(message: '词书数据同步成功');
        }
      }

      if (result.success && result.data != null) {
        // todo::这个是不是干掉？
        // 更新最后同步时间
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
      }

      return result;
    } catch (e) {
      return SyncResult.failure('同步失败: $e');
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

  /// 上传数据到对象存储
  Future<SyncResult> uploadData(
    SyncProvider provider,
    SyncDataType dataType,
    Map<String, dynamic> data, 
    void Function(String step, {int? current, int? total})? onProgress,
  ) async {
    try {
      _logDebug('开始上传数据，类型: $dataType');
      
      final pathPrefix = await provider.getPathPrefix();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final dataTypeName = dataType.toString().split('.').last;
      final objectKey = "$pathPrefix$dataTypeName-$timestamp.json";
      final latestKey = "$pathPrefix$dataTypeName-latest.json";
      final jsonData = jsonEncode(data);
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
      
      _logDebug('数据上传成功');
      return SyncResult.success(
        message: '数据上传成功',
        data: {'objectKey': objectKey, 'latestKey': latestKey},
      );
    } catch (e) {
      _logDebug('上传数据异常: $e');
      return SyncResult.failure('上传数据失败: $e');
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
    print('[WordbookSync] $message');
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
