import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';
import 'sync_service.dart';
import 'history_deletion_service.dart';
import 'wordbook_sync_service.dart';
import '../utils/file_hash_utils.dart';
import '../../shared/utils/path_utils.dart';

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

/// 对象存储同步提供商
class ObjectStorageSyncProvider extends SyncProvider {
  late final ObjectStorageConfig _storageConfig;
  late final String _baseUrl;
  final HistoryDeletionService _deletionService = HistoryDeletionService.instance;

  ObjectStorageSyncProvider(SyncConfig config) : super(config) {
    _storageConfig = ObjectStorageConfig.fromMap(config.settings);
    _baseUrl = _buildBaseUrl();
  }

  @override
  SyncProviderType get providerType => SyncProviderType.objectStorage;

  String _buildBaseUrl() {
    final protocol = _storageConfig.useSSL ? 'https' : 'http';
    if (_storageConfig.urlStyle == UrlStyle.hostStyle) {
      return '$protocol://${_storageConfig.bucket}.${_storageConfig.endpoint}';
    } else {
      return '$protocol://${_storageConfig.endpoint}';
    }
  }

  String _buildObjectUrl(String objectKey) {
    if (_storageConfig.urlStyle == UrlStyle.hostStyle) {
      // Host风格: https://bucket.endpoint/objectKey
      return '$_baseUrl/$objectKey';
    } else {
      // Path风格: https://endpoint/bucket/objectKey
      return '$_baseUrl/${_storageConfig.bucket}/$objectKey';
    }
  }

  void _logDebug(String message) {
    print('[ObjectStorageSync] $message');
  }

  String _getObjectKey(SyncDataType dataType) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final dataTypeName = dataType.toString().split('.').last;
    return '${_storageConfig.pathPrefix}/$dataTypeName-$timestamp.json';
  }

  String _getLatestObjectKey(SyncDataType dataType) {
    final dataTypeName = dataType.toString().split('.').last;
    return '${_storageConfig.pathPrefix}/$dataTypeName-latest.json';
  }

  String _getImageObjectKey(String hash, String extension) {
    return 'handwriting_cache/$hash$extension';
  }
  
  String _getFullImageObjectKey(String hash, String extension) {
    return '${_storageConfig.pathPrefix}/handwriting_cache/$hash$extension';
  }

  @override
  Future<SyncResult> testConnection() async {
    try {
      _logDebug('开始连接测试');
      _logDebug('存储类型: ${_storageConfig.storageType}');
      _logDebug('端点: ${_storageConfig.endpoint}');
      _logDebug('存储桶: ${_storageConfig.bucket}');
      _logDebug('URL风格: ${_storageConfig.urlStyle}');
      _logDebug('基础URL: $_baseUrl');
      
      // 尝试列出bucket中的对象来测试连接
      final result = await _listObjects(maxKeys: 1);
      if (result.success) {
        _logDebug('连接测试成功');
        return SyncResult.success(message: '连接测试成功');
      } else {
        _logDebug('连接测试失败: ${result.message}');
        return SyncResult.failure('连接测试失败: ${result.message}');
      }
    } catch (e) {
      _logDebug('连接测试异常: $e');
      return SyncResult.failure('连接测试失败: $e');
    }
  }

  @override
  Future<SyncResult> getDataInfo(SyncDataType dataType) async {
    try {
      final latestKey = _getLatestObjectKey(dataType);
      final result = await _headObject(latestKey);
      
      if (result.success) {
        return SyncResult.success(
          message: '获取数据信息成功',
          data: result.data,
        );
      } else {
        return SyncResult.failure('获取数据信息失败: ${result.message}');
      }
    } catch (e) {
      return SyncResult.failure('获取数据信息失败: $e');
    }
  }

  @override
  Future<SyncResult> listDataFiles() async {
    try {
      final result = await _listObjects(prefix: _storageConfig.pathPrefix);
      
      if (result.success) {
        return SyncResult.success(
          message: '获取文件列表成功',
          data: result.data,
        );
      } else {
        return SyncResult.failure('获取文件列表失败: ${result.message}');
      }
    } catch (e) {
      return SyncResult.failure('获取文件列表失败: $e');
    }
  }

  // 内部HTTP请求方法
  Future<SyncResult> _putObject(String objectKey, List<int> data, {String? contentType, void Function(int current, int total)? onProgress}) async {
    try {
      final url = _buildObjectUrl(objectKey);
      final headers = await _buildHeaders('PUT', objectKey, data);
      
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

  Future<SyncResult> _getObject(String objectKey, {void Function(int current, int total)? onProgress}) async {
    try {
      final url = _buildObjectUrl(objectKey);
      final headers = await _buildHeaders('GET', objectKey);
      
      final response = await http.get(
        Uri.parse(url),
        headers: headers,
      );
      
      if (response.statusCode == 200) {
        // 检查响应体是否为空
        if (response.bodyBytes.isEmpty) {
          return SyncResult.failure('服务器返回空响应');
        }
        
        // 如果有进度回调，调用完成状态
        final bytes = response.bodyBytes;
        onProgress?.call(bytes.length, bytes.length);
        
        return SyncResult.success(data: {
          'data': bytes, // 使用 'data' 字段名以与新方法保持一致
          'content': bytes, // 保留原有字段名以兼容现有代码
          'contentType': response.headers['content-type'],
          'lastModified': response.headers['last-modified'],
          'size': bytes.length,
        });
      } else if (response.statusCode == 404) {
        return SyncResult.failure('文件不存在');
      } else {
        _logDebug('GET请求失败: HTTP ${response.statusCode}');
        return SyncResult.failure('HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      _logDebug('GET请求异常: $e');
      return SyncResult.failure('GET请求失败: $e');
    }
  }

  Future<SyncResult> _deleteObject(String objectKey) async {
    try {
      final url = _buildObjectUrl(objectKey);
      _logDebug('DELETE请求URL: $url');
      final headers = await _buildHeaders('DELETE', objectKey);
      _logDebug('DELETE请求头: $headers');
      
      final response = await http.delete(
        Uri.parse(url),
        headers: headers,
      );

      _logDebug('DELETE响应状态码: ${response.statusCode}');
      if (response.statusCode == 204 || response.statusCode == 200) {
        return SyncResult.success();
      } else {
        _logDebug('DELETE响应内容: ${response.body}');
        return SyncResult.failure('HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      _logDebug('DELETE请求异常: $e');
      return SyncResult.failure('DELETE请求失败: $e');
    }
  }

  Future<SyncResult> _headObject(String objectKey) async {
    try {
      final url = _buildObjectUrl(objectKey);
      _logDebug('HEAD请求URL: $url');
      final headers = await _buildHeaders('HEAD', objectKey);
      _logDebug('HEAD请求头: $headers');
      
      final response = await http.head(
        Uri.parse(url),
        headers: headers,
      );

      _logDebug('HEAD响应状态码: ${response.statusCode}');
      if (response.statusCode == 200) {
        return SyncResult.success(data: {
          'contentLength': response.headers['content-length'],
          'contentType': response.headers['content-type'],
          'lastModified': response.headers['last-modified'],
          'etag': response.headers['etag'],
        });
      } else if (response.statusCode == 404) {
        return SyncResult.failure('文件不存在');
      } else {
        _logDebug('HEAD响应内容: ${response.body}');
        return SyncResult.failure('HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      _logDebug('HEAD请求异常: $e');
      return SyncResult.failure('HEAD请求失败: $e');
    }
  }

  /// 检查对象是否存在
  Future<bool> _checkObjectExists(String objectKey) async {
    final result = await _headObject(objectKey);
    return result.success;
  }

  Future<SyncResult> _listObjects({String? prefix, int maxKeys = 1000}) async {
    try {
      final queryParams = <String, String>{
        'list-type': '2',
        'max-keys': maxKeys.toString(),
      };
      if (prefix != null) {
        queryParams['prefix'] = prefix;
      }
      
      final query = queryParams.entries
          .map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
          .join('&');
      
      // 对于list操作，URL构建方式需要根据URL风格调整
      String url;
      if (_storageConfig.urlStyle == UrlStyle.hostStyle) {
        // Host风格: https://bucket.endpoint/?query
        url = '$_baseUrl/?$query';
      } else {
        // Path风格: https://endpoint/bucket?query
        url = '$_baseUrl/${_storageConfig.bucket}?$query';
      }
      
      final headers = await _buildHeaders('GET', '', null, queryParams);
      
      final response = await http.get(
        Uri.parse(url),
        headers: headers,
      );

      if (response.statusCode == 200) {
        // 这里应该解析XML响应，但为了简化，我们返回原始响应
        return SyncResult.success(data: {
          'response': response.body,
          'statusCode': response.statusCode,
        });
      } else {
        _logDebug('LIST请求失败: HTTP ${response.statusCode}');
        return SyncResult.failure('HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      _logDebug('LIST请求异常: $e');
      return SyncResult.failure('LIST请求失败: $e');
    }
  }

  Future<Map<String, String>> _buildHeaders(
    String method,
    String objectKey, [
    List<int>? body,
    Map<String, String>? queryParams,
  ]) async {
    // 根据URL风格设置正确的Host头
    String hostHeader;
    if (_storageConfig.urlStyle == UrlStyle.hostStyle) {
      hostHeader = '${_storageConfig.bucket}.${_storageConfig.endpoint}';
    } else {
      hostHeader = _storageConfig.endpoint;
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
    final signature = await _buildSignature(method, objectKey, headers, body, queryParams);
    headers['Authorization'] = signature;

    return headers;
  }

  String _getAmzDate() {
    return DateTime.now().toUtc().toIso8601String().replaceAll(RegExp(r'[:\-]'), '').split('.')[0] + 'Z';
  }

  Future<String> _buildSignature(
    String method,
    String objectKey,
    Map<String, String> headers,
    List<int>? body,
    Map<String, String>? queryParams,
  ) async {
    final accessKey = _storageConfig.accessKeyId;
    final secretKey = _storageConfig.secretAccessKey;
    final region = _storageConfig.region;
    final service = 's3';
    final date = DateTime.now().toUtc();
    final dateStamp = date.toIso8601String().substring(0, 10).replaceAll('-', '');
    final amzDate = headers['X-Amz-Date']!;
    
    // 1. 创建规范请求
    final canonicalUri = _getCanonicalUri(objectKey);
    final canonicalQueryString = _getCanonicalQueryString(queryParams);
    final canonicalHeaders = _getCanonicalHeaders(headers);
    final signedHeaders = _getSignedHeaders(headers);
    final payloadHash = _getPayloadHash(body);
    
    final canonicalRequest = '$method\n$canonicalUri\n$canonicalQueryString\n$canonicalHeaders\n$signedHeaders\n$payloadHash';
    
    // 2. 创建待签名字符串
    final algorithm = 'AWS4-HMAC-SHA256';
    final credentialScope = '$dateStamp/$region/$service/aws4_request';
    final canonicalRequestHash = _sha256Hash(canonicalRequest);
    
    final stringToSign = '$algorithm\n$amzDate\n$credentialScope\n$canonicalRequestHash';
    
    // 3. 计算签名
    final signingKey = _getSigningKey(secretKey, dateStamp, region, service);
    final signature = _hmacSha256Hex(signingKey, stringToSign);
    
    // 4. 构建授权头
    return '$algorithm Credential=$accessKey/$credentialScope, SignedHeaders=$signedHeaders, Signature=$signature';
  }
  
  String _getCanonicalUri(String objectKey) {
    if (_storageConfig.urlStyle == UrlStyle.hostStyle) {
      return '/' + Uri.encodeComponent(objectKey).replaceAll('%2F', '/');
    } else {
      return '/' + Uri.encodeComponent(_storageConfig.bucket) + '/' + Uri.encodeComponent(objectKey).replaceAll('%2F', '/');
    }
  }
  
  String _getCanonicalQueryString(Map<String, String>? queryParams) {
    if (queryParams == null || queryParams.isEmpty) {
      return '';
    }
    
    final sortedParams = queryParams.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    
    return sortedParams
        .map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');
  }
  
  String _getCanonicalHeaders(Map<String, String> headers) {
    final sortedHeaders = headers.entries
        .where((e) => e.key.toLowerCase().startsWith('host') || e.key.toLowerCase().startsWith('x-amz'))
        .toList()
      ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));
    
    return sortedHeaders
        .map((e) => '${e.key.toLowerCase()}:${e.value.trim()}\n')
        .join('');
  }
  
  String _getSignedHeaders(Map<String, String> headers) {
    final headerNames = headers.keys
        .where((key) => key.toLowerCase().startsWith('host') || key.toLowerCase().startsWith('x-amz'))
        .map((key) => key.toLowerCase())
        .toList()
      ..sort();
    
    return headerNames.join(';');
  }
  
  String _getPayloadHash(List<int>? body) {
    if (body == null) {
      return _sha256HashBytes([]);
    }
    return _sha256HashBytes(body);
  }
  
  String _sha256Hash(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
  
  String _sha256HashBytes(List<int> bytes) {
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
  
  List<int> _getSigningKey(String secretKey, String dateStamp, String region, String service) {
    final kDate = _hmacSha256('AWS4$secretKey', dateStamp);
    final kRegion = _hmacSha256(kDate, region);
    final kService = _hmacSha256(kRegion, service);
    final kSigning = _hmacSha256(kService, 'aws4_request');
    return kSigning;
  }
  
  List<int> _hmacSha256(dynamic key, String message) {
    final keyBytes = key is String ? utf8.encode(key) : key as List<int>;
    final messageBytes = utf8.encode(message);
    final hmac = Hmac(sha256, keyBytes);
    return hmac.convert(messageBytes).bytes;
  }
  
  String _hmacSha256Hex(List<int> key, String message) {
    final messageBytes = utf8.encode(message);
    final hmac = Hmac(sha256, key);
    return hmac.convert(messageBytes).toString();
  }

  /// 删除历史记录关联的图片文件
  Future<void> _deleteAssociatedImageFiles(String historyDataKey) async {
    try {
      _logDebug('开始删除历史记录关联的图片文件: $historyDataKey');
      
      // 先下载历史记录数据以获取图片文件列表
      final downloadResult = await _getObject(historyDataKey);
      if (!downloadResult.success || downloadResult.data == null) {
        _logDebug('无法下载历史记录数据，跳过图片文件删除');
        return;
      }
      
      final contentBytes = downloadResult.data!['content'] as List<int>;
      final jsonString = utf8.decode(contentBytes);
      final historyData = jsonDecode(jsonString) as Map<String, dynamic>;
      
      // 收集所有图片文件的对象键
      final imageObjectKeys = <String>{};
      final sessions = historyData['sessions'] as List<dynamic>? ?? [];
      
      for (final session in sessions) {
        final sessionMap = session as Map<String, dynamic>;
        final results = sessionMap['results'] as List<dynamic>? ?? [];
        
        for (final result in results) {
          final resultMap = result as Map<String, dynamic>;
          
          // 收集原始图片对象键
          final originalObjectKey = resultMap['original_image_object_key'] as String?;
          if (originalObjectKey != null && originalObjectKey.isNotEmpty) {
            imageObjectKeys.add(originalObjectKey);
          }
          
          // 收集批改图片对象键
          final annotatedObjectKey = resultMap['annotated_image_object_key'] as String?;
          if (annotatedObjectKey != null && annotatedObjectKey.isNotEmpty) {
            imageObjectKeys.add(annotatedObjectKey);
          }
        }
      }
      
      _logDebug('找到 ${imageObjectKeys.length} 个图片文件需要删除');
      
      // 删除所有图片文件
      int deletedCount = 0;
      for (final objectKey in imageObjectKeys) {
        try {
          // 如果是相对路径，转换为完整路径
          final fullObjectKey = objectKey.startsWith(_storageConfig.pathPrefix) 
              ? objectKey 
              : '${_storageConfig.pathPrefix}/$objectKey';
          
          final deleteResult = await _deleteObject(fullObjectKey);
          if (deleteResult.success) {
            deletedCount++;
            _logDebug('删除图片文件成功: $objectKey');
          } else {
            _logDebug('删除图片文件失败: $objectKey, ${deleteResult.message}');
          }
        } catch (e) {
          _logDebug('删除图片文件异常: $objectKey, $e');
        }
      }
      
      _logDebug('图片文件删除完成，成功删除 $deletedCount/${imageObjectKeys.length} 个文件');
    } catch (e) {
      _logDebug('删除关联图片文件时发生异常: $e');
      // 不抛出异常，允许继续删除历史记录数据
    }
  }

  // ========== 纯文件存储操作方法实现 ==========

  @override
  Future<SyncResult> uploadFile(String filePath, String remotePath, {void Function(int current, int total)? onProgress}) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return SyncResult.failure('本地文件不存在: $filePath');
      }

      final bytes = await file.readAsBytes();
      final objectKey = '${_storageConfig.pathPrefix}/$remotePath';
      
      _logDebug('上传文件: $filePath -> $objectKey');
      
      final result = await _putObject(objectKey, bytes, onProgress: onProgress);
      if (result.success) {
        _logDebug('文件上传成功: $objectKey');
        return SyncResult.success(message: '文件上传成功', data: {'objectKey': objectKey, 'size': bytes.length});
      } else {
        return SyncResult.failure('文件上传失败: ${result.message}');
      }
    } catch (e) {
      _logDebug('上传文件异常: $e');
      return SyncResult.failure('上传文件失败: $e');
    }
  }

  @override
  Future<SyncResult> downloadFile(String remotePath, String localPath, {void Function(int current, int total)? onProgress}) async {
    try {
      final objectKey = '${_storageConfig.pathPrefix}/$remotePath';
      
      _logDebug('下载文件: $objectKey -> $localPath');
      
      final result = await _getObject(objectKey, onProgress: onProgress);
      if (result.success && result.data != null) {
        final bytes = result.data!['data'] as List<int>;
        
        // 确保目录存在
        final file = File(localPath);
        await file.parent.create(recursive: true);
        
        await file.writeAsBytes(bytes);
        
        _logDebug('文件下载成功: $localPath');
        return SyncResult.success(message: '文件下载成功', data: {'localPath': localPath, 'size': bytes.length});
      } else {
        return SyncResult.failure('文件下载失败: ${result.message}');
      }
    } catch (e) {
      _logDebug('下载文件异常: $e');
      return SyncResult.failure('下载文件失败: $e');
    }
  }

  @override
  Future<SyncResult> deleteFile(String remotePath) async {
    try {
      final objectKey = '${_storageConfig.pathPrefix}/$remotePath';
      
      _logDebug('删除文件: $objectKey');
      
      final result = await _deleteObject(objectKey);
      if (result.success) {
        _logDebug('文件删除成功: $objectKey');
        return SyncResult.success(message: '文件删除成功', data: {'objectKey': objectKey});
      } else {
        return SyncResult.failure('文件删除失败: ${result.message}');
      }
    } catch (e) {
      _logDebug('删除文件异常: $e');
      return SyncResult.failure('删除文件失败: $e');
    }
  }

  @override
  Future<SyncResult> uploadBytes(List<int> data, String remotePath, {String? contentType, void Function(int current, int total)? onProgress}) async {
    try {
      final objectKey = '${_storageConfig.pathPrefix}/$remotePath';
      
      _logDebug('上传字节数据: $objectKey (${data.length} bytes)');
      
      final result = await _putObject(objectKey, data, contentType: contentType, onProgress: onProgress);
      if (result.success) {
        _logDebug('字节数据上传成功: $objectKey');
        return SyncResult.success(message: '数据上传成功', data: {'objectKey': objectKey, 'size': data.length});
      } else {
        return SyncResult.failure('数据上传失败: ${result.message}');
      }
    } catch (e) {
      _logDebug('上传字节数据异常: $e');
      return SyncResult.failure('上传数据失败: $e');
    }
  }

  @override
  Future<SyncResult> downloadBytes(String remotePath, {void Function(int current, int total)? onProgress}) async {
    try {
      final objectKey = '${_storageConfig.pathPrefix}/$remotePath';
      
      _logDebug('下载字节数据: $objectKey');
      
      final result = await _getObject(objectKey, onProgress: onProgress);
      print('result:$result');
      if (result.success && result.data != null) {
        final bytes = result.data!['data'] as List<int>;
        
        _logDebug('字节数据下载成功: $objectKey (${bytes.length} bytes)');
        return SyncResult.success(message: '数据下载成功', data: result.data);
      } else {
        return SyncResult.failure('数据下载失败: ${result.message}');
      }
    } catch (e) {
      _logDebug('下载字节数据异常: $e');
      return SyncResult.failure('下载数据失败: $e');
    }
  }

  @override
  Future<SyncResult> fileExists(String remotePath) async {
    try {
      final objectKey = '${_storageConfig.pathPrefix}/$remotePath';
      
      _logDebug('检查文件是否存在: $objectKey');
      
      final result = await _headObject(objectKey);
      if (result.success) {
        _logDebug('文件存在: $objectKey');
        return SyncResult.success(message: '文件存在', data: {'exists': true, 'objectKey': objectKey});
      } else {
        _logDebug('文件不存在: $objectKey');
        return SyncResult.success(message: '文件不存在', data: {'exists': false, 'objectKey': objectKey});
      }
    } catch (e) {
      _logDebug('检查文件存在异常: $e');
      return SyncResult.failure('检查文件失败: $e');
    }
  }

  @override
  Future<SyncResult> getFileInfo(String remotePath) async {
    try {
      final objectKey = '${_storageConfig.pathPrefix}/$remotePath';
      
      _logDebug('获取文件信息: $objectKey');
      
      final result = await _headObject(objectKey);
      if (result.success && result.data != null) {
        _logDebug('获取文件信息成功: $objectKey');
        return SyncResult.success(message: '获取文件信息成功', data: result.data);
      } else {
        return SyncResult.failure('获取文件信息失败: ${result.message}');
      }
    } catch (e) {
      _logDebug('获取文件信息异常: $e');
      return SyncResult.failure('获取文件信息失败: $e');
    }
  }

  @override
  Future<SyncResult> listFiles(String remotePath, {bool recursive = false}) async {
    try {
      final prefix = '${_storageConfig.pathPrefix}/$remotePath';
      
      _logDebug('列出文件: $prefix (recursive: $recursive)');
      
      final result = await _listObjects(prefix: prefix);
      if (result.success && result.data != null) {
        final objects = result.data!['objects'] as List<Map<String, dynamic>>;
        
        // 过滤文件：如果不是递归模式，只返回直接子文件
        List<Map<String, dynamic>> filteredObjects = objects;
        if (!recursive) {
          filteredObjects = objects.where((obj) {
            final key = obj['key'] as String;
            final relativePath = key.startsWith('${_storageConfig.pathPrefix}/') 
                ? key.substring('${_storageConfig.pathPrefix}/'.length)
                : key;
            // 检查是否为直接子文件（不包含额外的斜杠）
            final pathAfterRemote = relativePath.startsWith('$remotePath/') 
                ? relativePath.substring('$remotePath/'.length)
                : relativePath;
            return !pathAfterRemote.contains('/');
          }).toList();
        }
        
        // 移除路径前缀，返回相对路径
        final files = filteredObjects.map((obj) {
          final key = obj['key'] as String;
          final relativePath = key.startsWith('${_storageConfig.pathPrefix}/') 
              ? key.substring('${_storageConfig.pathPrefix}/'.length)
              : key;
          return {
            ...obj,
            'relativePath': relativePath,
          };
        }).toList();
        
        _logDebug('列出文件成功: ${files.length} 个文件');
        return SyncResult.success(message: '列出文件成功', data: {'files': files});
      } else {
        return SyncResult.failure('列出文件失败: ${result.message}');
      }
    } catch (e) {
      _logDebug('列出文件异常: $e');
      return SyncResult.failure('列出文件失败: $e');
    }
  }

  @override
  Future<String> getPathPrefix() async {
    return '${_storageConfig.pathPrefix}/';
  }
}