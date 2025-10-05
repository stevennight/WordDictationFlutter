import 'dart:convert';

import 'import_data_service.dart';
import 'json_data_service.dart';
import 'sync_service.dart';

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
        // 更新最后同步时间
        await syncService.updateConfigLastSyncTime(configId);
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
      
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final dataTypeName = dataType.toString().split('.').last;
      final objectKey = "backup/$dataTypeName-$timestamp.json";
      final latestKey = "$dataTypeName-latest.json";
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
      
      // 清理旧的备份文件
      _logDebug('开始清理旧的备份文件');
      // 获取配置中的保留数量
      final syncService = SyncService();
      final config = syncService.configs.firstWhere((c) => c.settings == provider.config.settings, orElse: () => provider.config);
      final retentionCount = config.retentionCount;
      final cleanupResult = await cleanupOldBackups(provider, dataType, retentionCount);
      if (cleanupResult.success) {
        _logDebug('备份文件清理成功: ${cleanupResult.message}');
      } else {
        _logDebug('备份文件清理失败: ${cleanupResult.message}');
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

  /// 清理旧的备份文件，保留指定数量的最新备份
  /// [provider] 同步提供者
  /// [dataType] 数据类型
  /// [retentionCount] 保留的备份数量
  Future<SyncResult> cleanupOldBackups(SyncProvider provider, SyncDataType dataType, int retentionCount) async {
    try {
      final dataTypeName = dataType.toString().split('.').last;
      _logDebug('开始清理旧的 $dataTypeName 备份文件，保留 $retentionCount 份');
      
      // 列出backup目录下的所有备份文件
      final listResult = await provider.listFiles('backup', recursive: false);
      if (!listResult.success) {
        return SyncResult.failure('获取文件列表失败: ${listResult.message}');
      }
      
      final files = listResult.data!['files'] as List<Map<String, dynamic>>;
      
      // 过滤出指定类型的带时间戳的备份文件
      final backupFiles = files.where((file) {
        final relativePath = file['relativePath'] as String;
        final regex = RegExp(r'^' + dataTypeName + r'-(\d+)\.json$');
        return regex.hasMatch(relativePath);
      }).toList();
      
      _logDebug('找到 ${backupFiles.length} 个 $dataTypeName 备份文件');
      
      if (backupFiles.length <= retentionCount) {
        _logDebug('备份文件数量不超过保留数量，无需清理');
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
      _logDebug('需要删除 ${filesToDelete.length} 个旧备份文件');
      
      int deletedCount = 0;
      for (final file in filesToDelete) {
        final relativePath = file['relativePath'] as String;
        try {
          // 构建完整的备份文件路径
          final backupFilePath = 'backup/$relativePath';
          final deleteResult = await provider.deleteFile(backupFilePath);
          if (deleteResult.success) {
            deletedCount++;
            _logDebug('已删除旧备份文件: $relativePath');
          } else {
            _logDebug('删除备份文件失败: $relativePath, ${deleteResult.message}');
          }
        } catch (e) {
          _logDebug('删除备份文件异常: $relativePath, $e');
        }
      }
      
      _logDebug('备份文件清理完成，删除了 $deletedCount 个文件');
      return SyncResult.success(message: '清理完成，删除了 $deletedCount 个旧备份文件');
    } catch (e) {
      _logDebug('清理备份文件时发生错误: $e');
      return SyncResult.failure('清理备份文件失败: $e');
    }
  }
}
