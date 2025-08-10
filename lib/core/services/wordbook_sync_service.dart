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
        result = await provider.downloadData(SyncDataType.wordbooks);
        
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

  // /// 获取对象键
  // String _getObjectKey(SyncDataType dataType, ObjectStorageConfig storageConfig) {
  //   final timestamp = DateTime.now().millisecondsSinceEpoch;
  //   final dataTypeName = dataType.toString().split('.').last;
  //   return '${storageConfig.pathPrefix}/$dataTypeName-$timestamp.json';
  // }

  // /// 获取最新对象键
  // String _getLatestObjectKey(SyncDataType dataType, ObjectStorageConfig storageConfig) {
  //   final dataTypeName = dataType.toString().split('.').last;
  //   if (dataType == SyncDataType.historyImages) {
  //     return '${storageConfig.pathPrefix}/handwriting_cache/index.json';
  //   }
  //   return '${storageConfig.pathPrefix}/';
  // }

  /// 上传对象到存储
  Future<SyncResult> _putObject(
    String objectKey, 
    List<int> data, 
    ObjectStorageConfig storageConfig,
    {String? contentType, void Function(int current, int total)? onProgress}
  ) async {
    try {
      final url = _buildObjectUrl(objectKey, storageConfig);
      final headers = await _buildHeaders('PUT', objectKey, storageConfig, data);
      
      // 如果指定了内容类型，添加到headers中
      if (contentType != null) {
        headers['Content-Type'] = contentType;
      }
      
      // 如果有进度回调，先调用开始状态
      onProgress?.call(0, data.length);
      
      final response = await http.put(
        Uri.parse(url),
        headers: headers,
        body: data,
      );
      
      // 上传完成后调用进度回调
      onProgress?.call(data.length, data.length);

      if (response.statusCode == 200 || response.statusCode == 201) {
        return SyncResult.success();
      } else {
        _logDebug('PUT请求失败: HTTP ${response.statusCode}');
        return SyncResult.failure('HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      _logDebug('PUT请求异常: $e');
      return SyncResult.failure('PUT请求失败: $e');
    }
  }

  /// 构建对象URL
  String _buildObjectUrl(String objectKey, ObjectStorageConfig storageConfig) {
    final baseUrl = _buildBaseUrl(storageConfig);
    if (storageConfig.urlStyle == UrlStyle.hostStyle) {
      // Host风格: https://bucket.endpoint/objectKey
      return '$baseUrl/$objectKey';
    } else {
      // Path风格: https://endpoint/bucket/objectKey
      return '$baseUrl/${storageConfig.bucket}/$objectKey';
    }
  }

  /// 构建基础URL
  String _buildBaseUrl(ObjectStorageConfig storageConfig) {
    final protocol = storageConfig.useSSL ? 'https' : 'http';
    if (storageConfig.urlStyle == UrlStyle.hostStyle) {
      return '$protocol://${storageConfig.bucket}.${storageConfig.endpoint}';
    } else {
      return '$protocol://${storageConfig.endpoint}';
    }
  }

  /// 构建请求头
  Future<Map<String, String>> _buildHeaders(
    String method,
    String objectKey,
    ObjectStorageConfig storageConfig, [
    List<int>? body,
    Map<String, String>? queryParams,
  ]) async {
    // 根据URL风格设置正确的Host头
    String hostHeader;
    if (storageConfig.urlStyle == UrlStyle.hostStyle) {
      hostHeader = '${storageConfig.bucket}.${storageConfig.endpoint}';
    } else {
      hostHeader = storageConfig.endpoint;
    }
    
    final headers = <String, String>{
      'Host': hostHeader,
      'X-Amz-Date': _getAmzDate(),
    };
    
    // 计算并设置content-sha256头
    final payloadHash = _getPayloadHash(body);
    headers['x-amz-content-sha256'] = payloadHash;

    if (body != null) {
      headers['Content-Length'] = body.length.toString();
      headers['Content-Type'] = 'application/json';
    }

    // 构建AWS签名v4
    final signature = await _buildSignature(method, objectKey, storageConfig, headers, body, queryParams);
    headers['Authorization'] = signature;

    return headers;
  }

  /// 获取AMZ日期格式
  String _getAmzDate() {
    return DateTime.now().toUtc().toIso8601String().replaceAll(RegExp(r'[:\-]'), '').split('.')[0] + 'Z';
  }

  /// 获取负载哈希
  String _getPayloadHash(List<int>? body) {
    if (body == null || body.isEmpty) {
      return sha256.convert([]).toString();
    }
    return sha256.convert(body).toString();
  }

  /// 构建AWS签名v4
  Future<String> _buildSignature(
    String method,
    String objectKey,
    ObjectStorageConfig storageConfig,
    Map<String, String> headers,
    List<int>? body,
    Map<String, String>? queryParams,
  ) async {
    final accessKey = storageConfig.accessKeyId;
    final secretKey = storageConfig.secretAccessKey;
    final region = storageConfig.region;
    final service = 's3';
    final date = DateTime.now().toUtc();
    final dateStamp = date.toIso8601String().substring(0, 10).replaceAll('-', '');
    final amzDate = headers['X-Amz-Date']!;
    
    // 1. 创建规范请求
    final canonicalUri = _getCanonicalUri(objectKey);
    final canonicalQueryString = _getCanonicalQueryString(queryParams);
    final canonicalHeaders = _getCanonicalHeaders(headers);
    final signedHeaders = _getSignedHeaders(headers);
    final payloadHash = headers['x-amz-content-sha256']!;
    
    final canonicalRequest = '$method\n$canonicalUri\n$canonicalQueryString\n$canonicalHeaders\n$signedHeaders\n$payloadHash';
    
    // 2. 创建待签名字符串
    final algorithm = 'AWS4-HMAC-SHA256';
    final credentialScope = '$dateStamp/$region/$service/aws4_request';
    final stringToSign = '$algorithm\n$amzDate\n$credentialScope\n${sha256.convert(utf8.encode(canonicalRequest))}';
    
    // 3. 计算签名
    final signingKey = _getSignatureKey(secretKey, dateStamp, region, service);
    final signature = _hmacSha256(signingKey, utf8.encode(stringToSign));
    
    // 4. 构建Authorization头
    return '$algorithm Credential=$accessKey/$credentialScope, SignedHeaders=$signedHeaders, Signature=${signature.toString()}';
  }

  /// 获取规范URI
  String _getCanonicalUri(String objectKey) {
    return '/' + Uri.encodeComponent(objectKey).replaceAll('%2F', '/');
  }

  /// 获取规范查询字符串
  String _getCanonicalQueryString(Map<String, String>? queryParams) {
    if (queryParams == null || queryParams.isEmpty) {
      return '';
    }
    
    final sortedKeys = queryParams.keys.toList()..sort();
    final pairs = <String>[];
    
    for (final key in sortedKeys) {
      final encodedKey = Uri.encodeComponent(key);
      final encodedValue = Uri.encodeComponent(queryParams[key]!);
      pairs.add('$encodedKey=$encodedValue');
    }
    
    return pairs.join('&');
  }

  /// 获取规范头部
  String _getCanonicalHeaders(Map<String, String> headers) {
    final sortedKeys = headers.keys.map((k) => k.toLowerCase()).toList()..sort();
    final canonicalHeaders = <String>[];
    
    for (final key in sortedKeys) {
      final originalKey = headers.keys.firstWhere((k) => k.toLowerCase() == key);
      final value = headers[originalKey]!.trim();
      canonicalHeaders.add('$key:$value');
    }
    
    return canonicalHeaders.join('\n') + '\n';
  }

  /// 获取已签名头部
  String _getSignedHeaders(Map<String, String> headers) {
    final sortedKeys = headers.keys.map((k) => k.toLowerCase()).toList()..sort();
    return sortedKeys.join(';');
  }

  /// 获取签名密钥
  List<int> _getSignatureKey(String key, String dateStamp, String regionName, String serviceName) {
    final kDate = _hmacSha256(utf8.encode('AWS4$key'), utf8.encode(dateStamp));
    final kRegion = _hmacSha256(kDate, utf8.encode(regionName));
    final kService = _hmacSha256(kRegion, utf8.encode(serviceName));
    final kSigning = _hmacSha256(kService, utf8.encode('aws4_request'));
    return kSigning;
  }

  /// HMAC-SHA256计算
  List<int> _hmacSha256(List<int> key, List<int> data) {
    final hmac = Hmac(sha256, key);
    return hmac.convert(data).bytes;
  }
}

/// 对象存储类型
enum ObjectStorageType {
  awsS3,
  alibabaOSS,
  tencentCOS,
  minIO,
  custom, // 自定义兼容S3的存储
}

/// URL 风格类型
enum UrlStyle {
  pathStyle,    // 路径风格: https://endpoint/bucket/key
  hostStyle,    // 主机风格: https://bucket.endpoint/key
}

/// 对象存储配置
class ObjectStorageConfig {
  final ObjectStorageType storageType;
  final String endpoint;
  final String region;
  final String bucket;
  final String accessKeyId;
  final String secretAccessKey;
  final String? sessionToken;
  final bool useSSL;
  final String pathPrefix; // 存储路径前缀
  final UrlStyle urlStyle; // URL 风格

  ObjectStorageConfig({
    required this.storageType,
    required this.endpoint,
    required this.region,
    required this.bucket,
    required this.accessKeyId,
    required this.secretAccessKey,
    this.sessionToken,
    this.useSSL = true,
    this.pathPrefix = 'wordDictationSync',
    this.urlStyle = UrlStyle.pathStyle,
  });

  Map<String, dynamic> toMap() {
    return {
      'storageType': storageType.toString(),
      'endpoint': endpoint,
      'region': region,
      'bucket': bucket,
      'accessKeyId': accessKeyId,
      'secretAccessKey': secretAccessKey,
      'sessionToken': sessionToken,
      'useSSL': useSSL,
      'pathPrefix': pathPrefix,
      'urlStyle': urlStyle.toString(),
    };
  }

  factory ObjectStorageConfig.fromMap(Map<String, dynamic> map) {
    return ObjectStorageConfig(
      storageType: ObjectStorageType.values.firstWhere(
        (e) => e.toString() == map['storageType'],
        orElse: () => ObjectStorageType.custom,
      ),
      endpoint: map['endpoint'],
      region: map['region'],
      bucket: map['bucket'],
      accessKeyId: map['accessKeyId'],
      secretAccessKey: map['secretAccessKey'],
      sessionToken: map['sessionToken'],
      useSSL: map['useSSL'] ?? true,
      pathPrefix: map['pathPrefix'] ?? 'wordDictationSync',
      urlStyle: UrlStyle.values.firstWhere(
        (e) => e.toString() == map['urlStyle'],
        orElse: () => UrlStyle.pathStyle,
      ),
    );
  }
}