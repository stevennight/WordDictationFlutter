import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'sync_service.dart';
import 'history_deletion_service.dart';
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
    if (dataType == SyncDataType.historyImages) {
      return '${_storageConfig.pathPrefix}/handwriting_cache/index.json';
    }
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
  Future<SyncResult> uploadData(SyncDataType dataType, Map<String, dynamic> data, void Function(String step, {int? current, int? total})? onProgress,) async {
    try {
      _logDebug('开始上传数据，类型: $dataType');
      
      // 特殊处理历史记录图片上传
      if (dataType == SyncDataType.historyImages) {
        return await _uploadImageData(data);
      }
      
      // 特殊处理历史记录数据上传（包含图片文件）
      if (dataType == SyncDataType.history) {
        return await _uploadHistoryData(data, onProgress);
      }

      final objectKey = _getObjectKey(dataType);
      final latestKey = _getLatestObjectKey(dataType);
      final jsonData = jsonEncode(data);
      final bytes = utf8.encode(jsonData);
      
      _logDebug('上传JSON数据，大小: ${bytes.length} bytes');

      // 上传带时间戳的文件
      final uploadResult = await _putObject(objectKey, bytes);
      if (!uploadResult.success) {
        _logDebug('上传主文件失败: ${uploadResult.message}');
        return uploadResult;
      }

      // 同时上传latest文件作为最新版本的快速访问
      final latestResult = await _putObject(latestKey, bytes);
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

  @override
  Future<SyncResult> downloadData(SyncDataType dataType) async {
    try {
      // 特殊处理历史记录图片下载
      if (dataType == SyncDataType.historyImages) {
        return await _downloadImageData();
      }

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
      
      // 如果是历史记录数据，需要先删除关联的图片文件
      if (dataType == SyncDataType.history) {
        await _deleteAssociatedImageFiles(latestKey);
        // 同时清空本地历史记录（使用统一的删除服务）
        await _deletionService.clearAllHistory(deleteImages: true);
      }
      
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
      final headers = await _buildHeaders('PUT', objectKey, data);
      
      final response = await http.put(
        Uri.parse(url),
        headers: headers,
        body: data,
      );

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

  Future<SyncResult> _getObject(String objectKey) async {
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
        
        return SyncResult.success(data: {
          'content': response.bodyBytes,
          'contentType': response.headers['content-type'],
          'lastModified': response.headers['last-modified'],
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

  // 上传历史记录数据（包含图片文件）
  Future<SyncResult> _uploadHistoryData(Map<String, dynamic> data, void Function(String step, {int? current, int? total})? onProgress) async {
    try {
      _logDebug('开始上传历史记录数据');
      
      final sessions = data['sessions'] as List<dynamic>? ?? [];
      
      // 如果是空数据（用于清空远端记录），需要先删除远端的关联图片文件
      if (sessions.isEmpty) {
        _logDebug('检测到空历史记录数据，将删除远端关联的图片文件');
        final latestKey = _getLatestObjectKey(SyncDataType.history);
        await _deleteAssociatedImageFiles(latestKey);
      }
      
      // 首先收集所有需要上传的图片文件
      final imagesToUpload = <String>{};
      
      for (final session in sessions) {
        final sessionMap = session as Map<String, dynamic>;
        final results = sessionMap['results'] as List<dynamic>? ?? [];
        
        for (final result in results) {
          final resultMap = result as Map<String, dynamic>;
          
          if (sessionMap['sessionData']['deleted'] == 1) {
            continue;
          }

          final originalPath = resultMap['original_image_path'] as String?;
          final annotatedPath = resultMap['annotated_image_path'] as String?;
          
          if (originalPath != null && originalPath.isNotEmpty) {
            imagesToUpload.add(originalPath);
          }
          if (annotatedPath != null && annotatedPath.isNotEmpty) {
            imagesToUpload.add(annotatedPath);
          }
        }
      }
      
      _logDebug('找到 ${imagesToUpload.length} 个图片文件需要上传');
      
      // 上传图片文件（基于MD5哈希值去重和改进的命名规则）
      final uploadedImages = <String, String>{}; // 原路径 -> 对象键
      final imageHashCache = <String, String>{}; // 哈希值 -> 对象键
      
      for (final imagePath in imagesToUpload) {
        onProgress?.call('正在上传图片: $imagePath', current: uploadedImages.length, total: imagesToUpload.length);

        // 将相对路径转换为绝对路径
        final absolutePath = await PathUtils.convertToAbsolutePath(imagePath);
        final imageFile = File(absolutePath);
        
        if (!await imageFile.exists()) {
          _logDebug('图片文件不存在，跳过: $imagePath');
          continue;
        }
        
        try {
          // 使用MD5计算文件哈希值
          final hash = await FileHashUtils.calculateFileMd5Async(imageFile);
          
          // 检查是否已经上传过相同哈希的文件
          if (imageHashCache.containsKey(hash)) {
            final existingObjectKey = imageHashCache[hash]!;
            uploadedImages[imagePath] = existingObjectKey;
            _logDebug('图片已存在相同哈希，复用对象键: $imagePath -> $existingObjectKey');
            continue;
          }
          
          // 使用改进的命名规则：原始文件名 + MD5前缀
          final relativeObjectKey = FileHashUtils.generateCloudObjectKey(imagePath, hash);
          final fullObjectKey = '${_storageConfig.pathPrefix}/$relativeObjectKey';
          
          // 检查远端是否已存在该对象键
          final existsResult = await _checkObjectExists(fullObjectKey);
          if (existsResult) {
            uploadedImages[imagePath] = relativeObjectKey;
            imageHashCache[hash] = relativeObjectKey;
            _logDebug('远端已存在相同文件，跳过上传: $imagePath -> $relativeObjectKey');
            continue;
          }
          
          // 读取文件字节用于上传
          final imageBytes = await imageFile.readAsBytes();
          _logDebug('上传图片: $imagePath -> $relativeObjectKey (${imageBytes.length} bytes)');
          
          final uploadResult = await _putObject(fullObjectKey, imageBytes);
          if (uploadResult.success) {
            uploadedImages[imagePath] = relativeObjectKey;
            imageHashCache[hash] = relativeObjectKey;
            _logDebug('图片上传成功: $relativeObjectKey');
          } else {
            _logDebug('图片上传失败: $imagePath, 错误: ${uploadResult.message}');
            // 继续上传其他图片，不因单个图片失败而中断
          }
        } catch (e) {
          _logDebug('上传图片异常: $imagePath, 错误: $e');
          // 继续上传其他图片
        }
      }
      
      _logDebug('成功上传 ${uploadedImages.length} 个图片文件');
      
      // 更新历史记录数据中的图片路径为对象键
      final updatedData = Map<String, dynamic>.from(data);
      final updatedSessions = <Map<String, dynamic>>[];
      
      for (final session in sessions) {
        final sessionMap = Map<String, dynamic>.from(session as Map<String, dynamic>);
        final results = sessionMap['results'] as List<dynamic>? ?? [];
        final updatedResults = <Map<String, dynamic>>[];
        
        for (final result in results) {
          final resultMap = Map<String, dynamic>.from(result as Map<String, dynamic>);
          
          // 更新图片路径为对象键，并添加MD5信息
          final originalPath = resultMap['original_image_path'] as String?;
          final annotatedPath = resultMap['annotated_image_path'] as String?;
          final originalMd5 = resultMap['original_image_md5'] as String?;
          final annotatedMd5 = resultMap['annotated_image_md5'] as String?;
          
          if (originalPath != null && uploadedImages.containsKey(originalPath)) {
            resultMap['original_image_object_key'] = uploadedImages[originalPath];
            if (originalMd5 != null) {
              resultMap['original_image_md5'] = originalMd5;
            }
          }
          if (annotatedPath != null && uploadedImages.containsKey(annotatedPath)) {
            resultMap['annotated_image_object_key'] = uploadedImages[annotatedPath];
            if (annotatedMd5 != null) {
              resultMap['annotated_image_md5'] = annotatedMd5;
            }
          }
          
          updatedResults.add(resultMap);
        }
        
        sessionMap['results'] = updatedResults;
        updatedSessions.add(sessionMap);
      }
      
      updatedData['sessions'] = updatedSessions;
      
      // 上传更新后的JSON数据
      final objectKey = _getObjectKey(SyncDataType.history);
      final latestKey = _getLatestObjectKey(SyncDataType.history);
      final jsonData = jsonEncode(updatedData);
      final bytes = utf8.encode(jsonData);
      
      _logDebug('上传历史记录JSON数据，大小: ${bytes.length} bytes');
      
      // 上传带时间戳的文件
      final uploadResult = await _putObject(objectKey, bytes);
      if (!uploadResult.success) {
        _logDebug('上传历史记录主文件失败: ${uploadResult.message}');
        return uploadResult;
      }
      
      // 同时上传latest文件
      final latestResult = await _putObject(latestKey, bytes);
      if (!latestResult.success) {
        _logDebug('上传历史记录latest文件失败: ${latestResult.message}');
        return SyncResult.failure('上传latest文件失败: ${latestResult.message}');
      }
      
      _logDebug('历史记录数据上传完成');
      
      return SyncResult.success(
        message: '历史记录上传成功',
        data: {
          'objectKey': objectKey,
          'latestKey': latestKey,
          'uploadedImages': uploadedImages.length,
          'totalImages': imagesToUpload.length,
        },
      );
    } catch (e) {
      _logDebug('上传历史记录数据异常: $e');
      return SyncResult.failure('上传历史记录数据失败: $e');
    }
  }

  // 图片上传的特殊处理方法
  Future<SyncResult> _uploadImageData(Map<String, dynamic> data) async {
    try {
      final images = data['images'] as List<dynamic>? ?? [];
      final uploadedImages = <Map<String, dynamic>>[];
      
      // 上传每个图片文件
      for (final imageData in images) {
        final imageMap = imageData as Map<String, dynamic>;
        final hash = imageMap['hash'] as String;
        final extension = imageMap['extension'] as String;
        final bytes = imageMap['bytes'] as List<int>;
        
        final objectKey = _getImageObjectKey(hash, extension);
        final uploadResult = await _putObject(objectKey, bytes);
        
        if (uploadResult.success) {
          uploadedImages.add({
            'hash': hash,
            'extension': extension,
            'objectKey': objectKey,
            'url': _buildObjectUrl(objectKey),
            'size': bytes.length,
          });
        } else {
          return SyncResult.failure('上传图片失败: ${uploadResult.message}');
        }
      }
      
      // 创建并上传索引文件
      final indexData = {
        'images': uploadedImages,
        'uploadTime': DateTime.now().toIso8601String(),
        'totalCount': uploadedImages.length,
      };
      
      final indexKey = _getLatestObjectKey(SyncDataType.historyImages);
      final indexBytes = utf8.encode(jsonEncode(indexData));
      final indexResult = await _putObject(indexKey, indexBytes);
      
      if (indexResult.success) {
        return SyncResult.success(
          message: '图片数据上传成功',
          data: {
            'uploadedImages': uploadedImages,
            'indexKey': indexKey,
          },
        );
      } else {
        return SyncResult.failure('上传索引文件失败: ${indexResult.message}');
      }
    } catch (e) {
      return SyncResult.failure('上传图片数据失败: $e');
    }
  }

  // 图片下载的特殊处理方法
  Future<SyncResult> _downloadImageData() async {
    try {
      // 首先下载索引文件
      final indexKey = _getLatestObjectKey(SyncDataType.historyImages);
      final indexResult = await _getObject(indexKey);
      
      if (!indexResult.success) {
        return SyncResult.failure('下载图片索引失败: ${indexResult.message}');
      }
      
      final indexBytes = indexResult.data!['content'] as List<int>;
      final indexJson = jsonDecode(utf8.decode(indexBytes)) as Map<String, dynamic>;
      final imageList = indexJson['images'] as List<dynamic>? ?? [];
      
      final downloadedImages = <Map<String, dynamic>>[];
      
      // 下载每个图片文件
      for (final imageInfo in imageList) {
        final imageMap = imageInfo as Map<String, dynamic>;
        final objectKey = imageMap['objectKey'] as String;
        final hash = imageMap['hash'] as String;
        final extension = imageMap['extension'] as String;
        
        final imageResult = await _getObject(objectKey);
        if (imageResult.success) {
          final imageBytes = imageResult.data!['content'] as List<int>;
          downloadedImages.add({
            'hash': hash,
            'extension': extension,
            'bytes': imageBytes,
            'size': imageBytes.length,
          });
        } else {
          _logDebug('下载图片失败: $objectKey, ${imageResult.message}');
          // 继续下载其他图片，不因单个图片失败而中断
        }
      }
      
      return SyncResult.success(
        message: '图片数据下载成功',
        data: {
          'images': downloadedImages,
          'totalCount': downloadedImages.length,
          'indexInfo': indexJson,
        },
      );
    } catch (e) {
      return SyncResult.failure('下载图片数据失败: $e');
    }
  }

  @override
  Future<SyncResult> deleteFileByPath(String objectKey) async {
    try {
      // 如果是相对路径，转换为完整路径
      final fullObjectKey = objectKey.startsWith(_storageConfig.pathPrefix) 
          ? objectKey 
          : '${_storageConfig.pathPrefix}/$objectKey';
      
      _logDebug('开始删除对象: $objectKey -> $fullObjectKey');
      
      final result = await _deleteObject(fullObjectKey);
      if (result.success) {
        _logDebug('删除对象成功: $objectKey');
        return SyncResult.success(message: '删除对象成功');
      } else {
        _logDebug('删除对象失败: $objectKey, ${result.message}');
        return SyncResult.failure('删除对象失败: ${result.message}');
      }
    } catch (e) {
      _logDebug('删除对象异常: $objectKey, $e');
      return SyncResult.failure('删除对象失败: $e');
    }
  }

  /// 通过对象键直接下载图片文件
  Future<SyncResult> downloadImageByObjectKey(String objectKey) async {
    try {
      // 如果是相对路径，转换为完整路径
      final fullObjectKey = objectKey.startsWith(_storageConfig.pathPrefix) 
          ? objectKey 
          : '${_storageConfig.pathPrefix}/$objectKey';
      
      _logDebug('开始下载图片: $objectKey -> $fullObjectKey');
      
      final result = await _getObject(fullObjectKey);
      if (!result.success) {
        _logDebug('下载图片失败: $objectKey, ${result.message}');
        return SyncResult.failure('下载图片失败: ${result.message}');
      }
      
      final imageBytes = result.data!['content'] as List<int>;
      _logDebug('图片下载成功: $objectKey (${imageBytes.length} bytes)');
      
      return SyncResult.success(
        message: '图片下载成功',
        data: {
          'content': imageBytes,
          'objectKey': objectKey,
          'size': imageBytes.length,
        },
      );
    } catch (e) {
      _logDebug('下载图片异常: $objectKey, $e');
      return SyncResult.failure('下载图片失败: $e');
    }
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
}