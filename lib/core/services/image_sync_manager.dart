import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'sync_service.dart';
import 'history_sync_service.dart';

/// 图片同步管理器
/// 负责处理历史记录中的笔迹图片文件的上传下载和去重
class ImageSyncManager {
  static final ImageSyncManager _instance = ImageSyncManager._internal();
  factory ImageSyncManager() => _instance;
  ImageSyncManager._internal();

  late Directory _appDocDir;
  late Directory _imagesCacheDir;

  /// 初始化管理器
  Future<void> initialize() async {
    _appDocDir = await getApplicationDocumentsDirectory();
    _imagesCacheDir = Directory(path.join(_appDocDir.path, 'images_cache'));
    
    // 确保缓存目录存在
    if (!await _imagesCacheDir.exists()) {
      await _imagesCacheDir.create(recursive: true);
    }
  }

  /// 批量上传图片文件
  /// 返回成功上传的文件路径列表
  Future<List<String>> uploadImages(
    List<ImageFileInfo> imageFiles,
    SyncProvider provider,
  ) async {
    final List<String> uploadedFiles = [];
    
    for (final imageInfo in imageFiles) {
      try {
        final success = await _uploadSingleImage(imageInfo, provider);
        if (success) {
          uploadedFiles.add(imageInfo.relativePath);
        }
      } catch (e) {
        print('上传图片失败: ${imageInfo.relativePath}, $e');
      }
    }
    
    return uploadedFiles;
  }

  /// 上传单个图片文件
  Future<bool> _uploadSingleImage(
    ImageFileInfo imageInfo,
    SyncProvider provider,
  ) async {
    final localPath = path.join(_appDocDir.path, imageInfo.relativePath);
    final file = File(localPath);
    
    if (!await file.exists()) {
      print('本地文件不存在: $localPath');
      return false;
    }
    
    // 检查远端是否已存在相同哈希的文件
    final remoteKey = 'images/${imageInfo.hash}${path.extension(localPath)}';
    final checkResult = await provider.getDataInfo(SyncDataType.historyImages);
    
    // 如果远端已存在相同哈希的文件，跳过上传
    if (checkResult.success && checkResult.data != null) {
      final existingFiles = checkResult.data!['files'] as Map<String, dynamic>? ?? {};
      if (existingFiles.containsKey(imageInfo.hash)) {
        print('远端已存在相同文件，跳过上传: ${imageInfo.relativePath}');
        return true;
      }
    }
    
    // 读取文件内容
    final bytes = await file.readAsBytes();
    
    // 构造上传数据
    final uploadData = {
      'hash': imageInfo.hash,
      'relativePath': imageInfo.relativePath,
      'size': imageInfo.size,
      'lastModified': imageInfo.lastModified.toIso8601String(),
      'content': bytes,
    };
    
    // 上传到远端
    final result = await provider.uploadData(SyncDataType.historyImages, uploadData);
    
    if (result.success) {
      print('图片上传成功: ${imageInfo.relativePath}');
      return true;
    } else {
      print('图片上传失败: ${imageInfo.relativePath}, ${result.message}');
      return false;
    }
  }

  /// 下载缺失的图片文件
  Future<void> downloadMissingImages(
    List<ImageFileInfo> requiredImages,
    SyncProvider provider,
  ) async {
    for (final imageInfo in requiredImages) {
      try {
        await _downloadSingleImage(imageInfo, provider);
      } catch (e) {
        print('下载图片失败: ${imageInfo.relativePath}, $e');
      }
    }
  }

  /// 下载单个图片文件
  Future<void> _downloadSingleImage(
    ImageFileInfo imageInfo,
    SyncProvider provider,
  ) async {
    final localPath = path.join(_appDocDir.path, imageInfo.relativePath);
    final file = File(localPath);
    
    // 如果本地文件已存在且哈希匹配，跳过下载
    if (await file.exists()) {
      final localHash = _calculateFileHash(file);
      if (localHash == imageInfo.hash) {
        print('本地文件已存在且哈希匹配，跳过下载: ${imageInfo.relativePath}');
        return;
      }
    }
    
    // 从远端下载文件
    final downloadData = {
      'hash': imageInfo.hash,
      'relativePath': imageInfo.relativePath,
    };
    
    final result = await provider.downloadData(SyncDataType.historyImages);
    
    if (result.success && result.data != null) {
      final content = result.data!['content'] as Uint8List?;
      if (content != null) {
        // 确保目录存在
        final dir = Directory(path.dirname(localPath));
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        
        // 写入文件
        await file.writeAsBytes(content);
        
        // 验证下载的文件哈希
        final downloadedHash = _calculateFileHash(file);
        if (downloadedHash == imageInfo.hash) {
          print('图片下载成功: ${imageInfo.relativePath}');
        } else {
          print('图片下载后哈希不匹配: ${imageInfo.relativePath}');
          await file.delete(); // 删除损坏的文件
        }
      }
    } else {
      print('图片下载失败: ${imageInfo.relativePath}, ${result.message}');
    }
  }

  /// 清理本地孤立文件
  /// 删除不再被任何历史记录引用的图片文件
  Future<void> cleanupOrphanedFiles(List<String> referencedPaths) async {
    try {
      final imagesDirs = [
        Directory(path.join(_appDocDir.path, 'dictation_images')),
        Directory(path.join(_appDocDir.path, 'images')),
        _imagesCacheDir,
      ];
      
      final Set<String> referencedSet = referencedPaths.toSet();
      int deletedCount = 0;
      
      for (final dir in imagesDirs) {
        if (await dir.exists()) {
          await for (final entity in dir.list(recursive: true)) {
            if (entity is File) {
              final relativePath = path.relative(entity.path, from: _appDocDir.path);
              if (!referencedSet.contains(relativePath)) {
                try {
                  await entity.delete();
                  deletedCount++;
                  print('删除孤立文件: $relativePath');
                } catch (e) {
                  print('删除文件失败: $relativePath, $e');
                }
              }
            }
          }
        }
      }
      
      print('清理完成，删除了 $deletedCount 个孤立文件');
    } catch (e) {
      print('清理孤立文件失败: $e');
    }
  }

  /// 获取图片文件信息
  Future<ImageFileInfo?> getImageFileInfo(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return null;
      }
      
      final stat = await file.stat();
      final hash = _calculateFileHash(file);
      
      // 计算相对路径
      final relativePath = path.relative(filePath, from: _appDocDir.path);
      
      return ImageFileInfo(
        relativePath: relativePath,
        hash: hash,
        size: stat.size,
        lastModified: stat.modified,
      );
    } catch (e) {
      print('获取图片文件信息失败: $filePath, $e');
      return null;
    }
  }

  /// 计算文件哈希值
  String _calculateFileHash(File file) {
    final bytes = file.readAsBytesSync();
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// 检查文件是否需要上传
  Future<bool> needsUpload(String filePath, String? remoteHash) async {
    if (remoteHash == null) return true;
    
    final file = File(filePath);
    if (!await file.exists()) return false;
    
    final localHash = _calculateFileHash(file);
    return localHash != remoteHash;
  }

  /// 压缩图片文件（可选功能）
  /// 在上传前对图片进行压缩以节省存储空间和传输时间
  Future<File?> compressImage(File originalFile, {int quality = 85}) async {
    try {
      // 这里可以使用image包进行图片压缩
      // 为了简化，暂时直接返回原文件
      return originalFile;
    } catch (e) {
      print('图片压缩失败: ${originalFile.path}, $e');
      return null;
    }
  }

  /// 获取缓存目录路径
  String get cacheDirectoryPath => _imagesCacheDir.path;

  /// 获取缓存目录大小
  Future<int> getCacheSize() async {
    int totalSize = 0;
    
    if (await _imagesCacheDir.exists()) {
      await for (final entity in _imagesCacheDir.list(recursive: true)) {
        if (entity is File) {
          final stat = await entity.stat();
          totalSize += stat.size;
        }
      }
    }
    
    return totalSize;
  }

  /// 清空缓存目录
  Future<void> clearCache() async {
    try {
      if (await _imagesCacheDir.exists()) {
        await _imagesCacheDir.delete(recursive: true);
        await _imagesCacheDir.create();
        print('图片缓存已清空');
      }
    } catch (e) {
      print('清空图片缓存失败: $e');
    }
  }
}