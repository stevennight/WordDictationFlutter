import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import 'sync_service.dart';

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
  Future<SyncResult> uploadData(SyncDataType dataType, Map<String, dynamic> data) async {
    try {
      final objectKey = _getObjectKey(dataType);
      final latestKey = _getLatestObjectKey(dataType);
      final jsonData = jsonEncode(data);
      final bytes = utf8.encode(jsonData);

      // 上传带时间戳的文件
      final uploadResult = await _putObject(objectKey, bytes);
      if (!uploadResult.success) {
        return uploadResult;
      }

      // 同时上传latest文件作为最新版本的快速访问
      final latestResult = await _putObject(latestKey, bytes);
      if (!latestResult.success) {
        return SyncResult.failure('上传latest文件失败: ${latestResult.message}');
      }

      return SyncResult.success(
        message: '数据上传成功',
        data: {'objectKey': objectKey, 'latestKey': latestKey},
      );
    } catch (e) {
      return SyncResult.failure('上传数据失败: $e');
    }
  }

  @override
  Future<SyncResult> downloadData(SyncDataType dataType) async {
    try {
      final latestKey = _getLatestObjectKey(dataType);
      final result = await _getObject(latestKey);
      
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

  @override
  Future<SyncResult> deleteData(SyncDataType dataType) async {
    try {
      final latestKey = _getLatestObjectKey(dataType);
      final result = await _deleteObject(latestKey);
      
      if (result.success) {
        return SyncResult.success(message: '数据删除成功');
      } else {
        return SyncResult.failure('删除数据失败: ${result.message}');
      }
    } catch (e) {
      return SyncResult.failure('删除数据失败: $e');
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
  Future<SyncResult> _putObject(String objectKey, List<int> data) async {
    try {
      final url = _buildObjectUrl(objectKey);
      _logDebug('PUT请求URL: $url');
      final headers = await _buildHeaders('PUT', objectKey, data);
      _logDebug('PUT请求头: $headers');
      
      final response = await http.put(
        Uri.parse(url),
        headers: headers,
        body: data,
      );

      _logDebug('PUT响应状态码: ${response.statusCode}');
      if (response.statusCode == 200 || response.statusCode == 201) {
        return SyncResult.success();
      } else {
        _logDebug('PUT响应内容: ${response.body}');
        return SyncResult.failure('HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      _logDebug('PUT请求异常: $e');
      return SyncResult.failure('PUT请求失败: $e');
    }
  }

  Future<SyncResult> _getObject(String objectKey) async {
    try {
      final url = _buildObjectUrl(objectKey);
      _logDebug('GET请求URL: $url');
      final headers = await _buildHeaders('GET', objectKey);
      _logDebug('GET请求头: $headers');
      
      final response = await http.get(
        Uri.parse(url),
        headers: headers,
      );

      _logDebug('GET响应状态码: ${response.statusCode}');
      _logDebug('GET响应头: ${response.headers}');
      _logDebug('GET响应体长度: ${response.bodyBytes.length}');
      
      if (response.statusCode == 200) {
        // 检查响应体是否为空
        if (response.bodyBytes.isEmpty) {
          _logDebug('警告: 响应体为空');
          return SyncResult.failure('服务器返回空响应');
        }
        
        // 记录响应体的前100字节用于调试
        final previewBytes = response.bodyBytes.take(100).toList();
        _logDebug('响应体前100字节: $previewBytes');
        
        try {
          // 尝试解码为字符串以检查内容
          final responseText = utf8.decode(response.bodyBytes);
          _logDebug('响应体文本长度: ${responseText.length}');
          _logDebug('响应体前200字符: ${responseText.length > 200 ? responseText.substring(0, 200) : responseText}');
        } catch (decodeError) {
          _logDebug('响应体UTF-8解码失败: $decodeError');
        }
        
        return SyncResult.success(data: {
          'content': response.bodyBytes,
          'contentType': response.headers['content-type'],
          'lastModified': response.headers['last-modified'],
        });
      } else if (response.statusCode == 404) {
        return SyncResult.failure('文件不存在');
      } else {
        _logDebug('GET响应内容: ${response.body}');
        return SyncResult.failure('HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e, stackTrace) {
      _logDebug('GET请求异常: $e');
      _logDebug('异常堆栈: $stackTrace');
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
      
      _logDebug('LIST请求URL: $url');
      final headers = await _buildHeaders('GET', '', null, queryParams);
      _logDebug('LIST请求头: $headers');
      
      final response = await http.get(
        Uri.parse(url),
        headers: headers,
      );

      _logDebug('LIST响应状态码: ${response.statusCode}');
      if (response.statusCode == 200) {
        _logDebug('LIST响应内容长度: ${response.body.length}');
        // 这里应该解析XML响应，但为了简化，我们返回原始响应
        return SyncResult.success(data: {
          'response': response.body,
          'statusCode': response.statusCode,
        });
      } else {
        _logDebug('LIST响应内容: ${response.body}');
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
    
    _logDebug('设置Host头: $hostHeader');

    // 计算并设置content-sha256头
    final payloadHash = _getPayloadHash(body);
    headers['x-amz-content-sha256'] = payloadHash;
    _logDebug('设置x-amz-content-sha256: $payloadHash');

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
    _logDebug('规范请求: $canonicalRequest');
    
    // 2. 创建待签名字符串
    final algorithm = 'AWS4-HMAC-SHA256';
    final credentialScope = '$dateStamp/$region/$service/aws4_request';
    final canonicalRequestHash = _sha256Hash(canonicalRequest);
    
    final stringToSign = '$algorithm\n$amzDate\n$credentialScope\n$canonicalRequestHash';
    _logDebug('待签名字符串: $stringToSign');
    
    // 3. 计算签名
    final signingKey = _getSigningKey(secretKey, dateStamp, region, service);
    final signature = _hmacSha256Hex(signingKey, stringToSign);
    _logDebug('计算的签名: $signature');
    
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
}