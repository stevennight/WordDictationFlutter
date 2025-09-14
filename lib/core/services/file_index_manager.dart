import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

import '../utils/file_hash_utils.dart';
import 'sync_service.dart';

/// 文件索引项
class FileIndexItem {
  final String relativePath;  // 相对路径
  final String md5Hash;       // MD5哈希值
  final int size;             // 文件大小
  final DateTime lastModified; // 最后修改时间
  final String? etag;         // ETag（如果有）

  FileIndexItem({
    required this.relativePath,
    required this.md5Hash,
    required this.size,
    required this.lastModified,
    this.etag,
  });

  Map<String, dynamic> toJson() {
    return {
      'relativePath': relativePath,
      'md5Hash': md5Hash,
      'size': size,
      'lastModified': lastModified.toIso8601String(),
      'etag': etag,
    };
  }

  factory FileIndexItem.fromJson(Map<String, dynamic> json) {
    return FileIndexItem(
      relativePath: json['relativePath'] as String,
      md5Hash: json['md5Hash'] as String,
      size: json['size'] as int,
      lastModified: DateTime.parse(json['lastModified'] as String),
      etag: json['etag'] as String?,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FileIndexItem &&
        other.relativePath == relativePath &&
        other.md5Hash == md5Hash &&
        other.size == size;
  }

  @override
  int get hashCode {
    return relativePath.hashCode ^ md5Hash.hashCode ^ size.hashCode;
  }
}

/// 文件索引
class FileIndex {
  final DateTime createdAt;
  final DateTime updatedAt;
  final Map<String, FileIndexItem> files; // 相对路径 -> 文件信息

  FileIndex({
    required this.createdAt,
    required this.updatedAt,
    required this.files,
  });

  Map<String, dynamic> toJson() {
    return {
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'files': files.map((key, value) => MapEntry(key, value.toJson())),
    };
  }

  factory FileIndex.fromJson(Map<String, dynamic> json) {
    final filesJson = json['files'] as Map<String, dynamic>;
    final files = <String, FileIndexItem>{};
    
    for (final entry in filesJson.entries) {
      files[entry.key] = FileIndexItem.fromJson(entry.value as Map<String, dynamic>);
    }

    return FileIndex(
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      files: files,
    );
  }

  /// 检查文件是否存在
  bool fileExists(String relativePath) {
    return files.containsKey(relativePath);
  }

  /// 获取文件信息
  FileIndexItem? getFileInfo(String relativePath) {
    return files[relativePath];
  }

  /// 添加或更新文件信息
  void updateFile(FileIndexItem item) {
    files[item.relativePath] = item;
  }

  /// 移除文件
  void removeFile(String relativePath) {
    files.remove(relativePath);
  }

  /// 获取所有文件路径
  List<String> getAllFilePaths() {
    return files.keys.toList();
  }

  /// 创建副本
  FileIndex copyWith({
    DateTime? createdAt,
    DateTime? updatedAt,
    Map<String, FileIndexItem>? files,
  }) {
    return FileIndex(
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      files: files ?? Map.from(this.files),
    );
  }
}

/// 文件索引管理器
class FileIndexManager {
  static const String _indexFileName = 'file_index.json';
  
  final String _localIndexPath;
  FileIndex? _localIndex;

  FileIndexManager(String appDataDir) 
      : _localIndexPath = path.join(appDataDir, _indexFileName);

  void _logDebug(String message) {
    print('[FileIndexManager] $message');
  }

  /// 初始化本地索引
  Future<void> initialize() async {
    await _loadLocalIndex();
  }

  /// 加载本地索引
  Future<void> _loadLocalIndex() async {
    try {
      final file = File(_localIndexPath);
      if (await file.exists()) {
        final jsonString = await file.readAsString();
        final jsonData = jsonDecode(jsonString) as Map<String, dynamic>;
        _localIndex = FileIndex.fromJson(jsonData);
        _logDebug('本地索引加载成功，包含 ${_localIndex!.files.length} 个文件');
      } else {
        _localIndex = FileIndex(
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          files: {},
        );
        _logDebug('本地索引文件不存在，创建新索引');
      }
    } catch (e) {
      _logDebug('加载本地索引失败: $e，创建新索引');
      _localIndex = FileIndex(
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        files: {},
      );
    }
  }

  /// 保存本地索引
  Future<void> _saveLocalIndex() async {
    if (_localIndex == null) return;
    
    try {
      final file = File(_localIndexPath);
      await file.parent.create(recursive: true);
      
      final jsonString = jsonEncode(_localIndex!.toJson());
      await file.writeAsString(jsonString);
      _logDebug('本地索引保存成功');
    } catch (e) {
      _logDebug('保存本地索引失败: $e');
      throw Exception('保存本地索引失败: $e');
    }
  }

  /// 从远端下载索引
  Future<FileIndex?> downloadRemoteIndex(SyncProvider provider) async {
    try {
      _logDebug('开始下载远端索引');
      
      final result = await provider.downloadBytes(_indexFileName);
      if (result.success && result.data != null) {
        final bytes = result.data!['data'] as List<int>;
        final jsonString = utf8.decode(bytes);
        final jsonData = jsonDecode(jsonString) as Map<String, dynamic>;
        final remoteIndex = FileIndex.fromJson(jsonData);
        
        _logDebug('远端索引下载成功，包含 ${remoteIndex.files.length} 个文件');
        return remoteIndex;
      } else {
        _logDebug('远端索引不存在或下载失败: ${result.message}');
        return null;
      }
    } catch (e) {
      _logDebug('下载远端索引失败: $e');
      return null;
    }
  }

  /// 上传索引到远端
  Future<SyncResult> uploadIndexToRemote(SyncProvider provider) async {
    if (_localIndex == null) {
      return SyncResult.failure('本地索引未初始化');
    }

    try {
      _logDebug('开始上传索引到远端');
      
      // 更新索引的更新时间
      _localIndex = _localIndex!.copyWith(updatedAt: DateTime.now());
      
      final jsonString = jsonEncode(_localIndex!.toJson());
      final bytes = utf8.encode(jsonString);
      
      final result = await provider.uploadBytes(
        bytes, 
        _indexFileName,
        contentType: 'application/json',
      );
      
      if (result.success) {
        // 保存更新后的本地索引
        await _saveLocalIndex();
        _logDebug('索引上传成功');
        return SyncResult.success(message: '索引上传成功');
      } else {
        _logDebug('索引上传失败: ${result.message}');
        return result;
      }
    } catch (e) {
      _logDebug('上传索引失败: $e');
      return SyncResult.failure('上传索引失败: $e');
    }
  }

  /// 检查本地文件是否存在于索引中
  bool fileExistsInIndex(String relativePath) {
    return _localIndex?.fileExists(relativePath) ?? false;
  }

  /// 获取本地索引中的文件信息
  FileIndexItem? getLocalFileInfo(String relativePath) {
    return _localIndex?.getFileInfo(relativePath);
  }

  /// 添加或更新本地索引中的文件
  Future<void> updateLocalFileIndex(String relativePath, String localFilePath) async {
    if (_localIndex == null) {
      await initialize();
    }

    try {
      final file = File(localFilePath);
      if (!await file.exists()) {
        _logDebug('本地文件不存在，无法更新索引: $localFilePath');
        return;
      }

      final stat = await file.stat();
      final md5Hash = await FileHashUtils.calculateFileMd5Async(file);
      
      final item = FileIndexItem(
        relativePath: relativePath,
        md5Hash: md5Hash,
        size: stat.size,
        lastModified: stat.modified,
      );

      _localIndex!.updateFile(item);
      _logDebug('更新本地索引: $relativePath');
    } catch (e) {
      _logDebug('更新本地索引失败: $relativePath, $e');
      throw Exception('更新本地索引失败: $e');
    }
  }

  /// 从本地索引中移除文件
  void removeFromLocalIndex(String relativePath) {
    _localIndex?.removeFile(relativePath);
    _logDebug('从本地索引移除文件: $relativePath');
  }

  /// 比较本地和远端索引，返回需要上传和下载的文件列表
  Map<String, List<String>> compareIndexes(FileIndex? remoteIndex) {
    final result = <String, List<String>>{
      'upload': <String>[],
      'download': <String>[],
    };

    if (_localIndex == null) {
      _logDebug('本地索引未初始化');
      return result;
    }

    final localFiles = _localIndex!.files;
    final remoteFiles = remoteIndex?.files ?? <String, FileIndexItem>{};

    // 检查需要上传的文件（本地有但远端没有，或者MD5不同）
    for (final entry in localFiles.entries) {
      final relativePath = entry.key;
      final localItem = entry.value;
      final remoteItem = remoteFiles[relativePath];

      if (remoteItem == null || remoteItem.md5Hash != localItem.md5Hash) {
        result['upload']!.add(relativePath);
      }
    }

    // 检查需要下载的文件（远端有但本地没有，或者MD5不同）
    for (final entry in remoteFiles.entries) {
      final relativePath = entry.key;
      final remoteItem = entry.value;
      final localItem = localFiles[relativePath];

      if (localItem == null || localItem.md5Hash != remoteItem.md5Hash) {
        result['download']!.add(relativePath);
      }
    }

    _logDebug('索引比较完成: 需要上传 ${result['upload']!.length} 个文件，需要下载 ${result['download']!.length} 个文件');
    return result;
  }

  /// 批量更新本地索引
  Future<void> batchUpdateLocalIndex(List<String> filePaths, String baseDir) async {
    if (_localIndex == null) {
      await initialize();
    }

    _logDebug('开始批量更新本地索引，共 ${filePaths.length} 个文件');
    
    for (final filePath in filePaths) {
      try {
        final absolutePath = path.isAbsolute(filePath) ? filePath : path.join(baseDir, filePath);
        await updateLocalFileIndex(filePath, absolutePath);
      } catch (e) {
        _logDebug('更新文件索引失败: $filePath, $e');
      }
    }

    await _saveLocalIndex();
    _logDebug('批量更新本地索引完成');
  }

  /// 获取本地索引
  FileIndex? get localIndex => _localIndex;
  
  /// 保存本地索引（公共方法）
  Future<void> saveLocalIndex() async {
    await _saveLocalIndex();
  }

  /// 清理本地索引（移除不存在的文件）
  Future<void> cleanupLocalIndex(String baseDir) async {
    if (_localIndex == null) return;

    final filesToRemove = <String>[];
    
    for (final relativePath in _localIndex!.files.keys) {
      final absolutePath = path.join(baseDir, relativePath);
      final file = File(absolutePath);
      
      if (!await file.exists()) {
        filesToRemove.add(relativePath);
      }
    }

    for (final filePath in filesToRemove) {
      removeFromLocalIndex(filePath);
    }

    if (filesToRemove.isNotEmpty) {
      await _saveLocalIndex();
      _logDebug('清理本地索引完成，移除了 ${filesToRemove.length} 个不存在的文件');
    }
  }

  /// 智能同步索引策略
  /// 根据本地和远端索引的时间戳决定是否需要同步
  Future<bool> shouldSyncIndex(SyncProvider provider) async {
    try {
      if (_localIndex == null) {
        _logDebug('本地索引不存在，需要同步');
        return true;
      }

      final remoteIndex = await downloadRemoteIndex(provider);
      if (remoteIndex == null) {
        _logDebug('远端索引不存在，需要上传本地索引');
        return true;
      }

      // 比较更新时间
      final localUpdated = _localIndex!.updatedAt;
      final remoteUpdated = remoteIndex.updatedAt;
      
      if (localUpdated.isAfter(remoteUpdated)) {
        _logDebug('本地索引更新，需要上传到远端');
        return true;
      } else if (remoteUpdated.isAfter(localUpdated)) {
        _logDebug('远端索引更新，需要下载到本地');
        // 更新本地索引
        _localIndex = remoteIndex;
        await _saveLocalIndex();
        return false;
      }

      _logDebug('本地和远端索引同步，无需更新');
      return false;
    } catch (e) {
      _logDebug('检查索引同步状态失败: $e');
      return true; // 出错时保守地选择同步
    }
  }

  /// 增量更新索引
  /// 只更新变化的文件，提高效率
  Future<void> incrementalUpdateIndex(List<String> changedFiles, String baseDir) async {
    if (_localIndex == null) {
      await initialize();
    }

    _logDebug('开始增量更新索引，共 ${changedFiles.length} 个文件');
    
    var updateCount = 0;
    for (final filePath in changedFiles) {
      try {
        final absolutePath = path.isAbsolute(filePath) ? filePath : path.join(baseDir, filePath);
        final file = File(absolutePath);
        
        if (await file.exists()) {
          await updateLocalFileIndex(filePath, absolutePath);
          updateCount++;
        } else {
          // 文件不存在，从索引中移除
          removeFromLocalIndex(filePath);
          updateCount++;
        }
      } catch (e) {
        _logDebug('增量更新文件索引失败: $filePath, $e');
      }
    }

    if (updateCount > 0) {
      await _saveLocalIndex();
      _logDebug('增量更新索引完成，更新了 $updateCount 个文件');
    }
  }

  /// 预热索引缓存
  /// 在应用启动时预加载常用文件的索引信息
  Future<void> preloadIndex(SyncProvider provider) async {
    try {
      _logDebug('开始预热索引缓存');
      
      // 检查是否需要同步
      final needSync = await shouldSyncIndex(provider);
      if (needSync) {
        // 如果本地索引较新，上传到远端
        if (_localIndex != null) {
          await uploadIndexToRemote(provider);
        }
      }
      
      _logDebug('索引缓存预热完成');
    } catch (e) {
      _logDebug('预热索引缓存失败: $e');
    }
  }

  /// 获取索引统计信息
  Map<String, dynamic> getIndexStats() {
    if (_localIndex == null) {
      return {
        'fileCount': 0,
        'totalSize': 0,
        'createdAt': null,
        'updatedAt': null,
      };
    }

    var totalSize = 0;
    for (final item in _localIndex!.files.values) {
      totalSize += item.size;
    }

    return {
      'fileCount': _localIndex!.files.length,
      'totalSize': totalSize,
      'createdAt': _localIndex!.createdAt.toIso8601String(),
      'updatedAt': _localIndex!.updatedAt.toIso8601String(),
    };
  }
}