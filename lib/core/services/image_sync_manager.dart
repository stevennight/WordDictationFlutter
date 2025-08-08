import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:path/path.dart' show dirname;
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
    // For desktop platforms, use executable directory
    // For mobile platforms, fallback to documents directory
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      // Get executable directory for desktop platforms
      final executablePath = Platform.resolvedExecutable;
      _appDocDir = Directory(dirname(executablePath));
    } else {
      // Fallback to documents directory for mobile platforms
      _appDocDir = await getApplicationDocumentsDirectory();
    }
    
    _imagesCacheDir = Directory(path.join(_appDocDir.path, 'handwriting_cache'));
    
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
    if (imageFiles.isEmpty) {
      return [];
    }

    try {
      // 准备批量上传的图片数据
      final List<Map<String, dynamic>> imagesToUpload = [];
      
      for (final imageInfo in imageFiles) {
        final localPath = path.join(_appDocDir.path, imageInfo.relativePath);
        final file = File(localPath);
        
        if (!await file.exists()) {
          print('本地文件不存在: $localPath');
          continue;
        }
        
        // 读取文件内容
        final bytes = await file.readAsBytes();
        final extension = path.extension(localPath);
        
        imagesToUpload.add({
          'hash': imageInfo.hash,
          'extension': extension,
          'bytes': bytes,
          'relativePath': imageInfo.relativePath,
          'size': imageInfo.size,
          'lastModified': imageInfo.lastModified.toIso8601String(),
        });
      }
      
      if (imagesToUpload.isEmpty) {
        print('没有有效的图片文件需要上传');
        return [];
      }
      
      // 批量上传图片
      final uploadData = {
        'images': imagesToUpload,
      };
      
      final result = await provider.uploadData(SyncDataType.historyImages, uploadData);
      
      if (result.success) {
        final uploadedPaths = imagesToUpload.map((img) => img['relativePath'] as String).toList();
        print('批量上传图片成功: ${uploadedPaths.length} 个文件');
        return uploadedPaths;
      } else {
        print('批量上传图片失败: ${result.message}');
        return [];
      }
    } catch (e) {
      print('批量上传图片异常: $e');
      return [];
    }
  }

  /// 上传单个图片文件（已弃用，使用批量上传）
  @deprecated
  Future<bool> _uploadSingleImage(
    ImageFileInfo imageInfo,
    SyncProvider provider,
  ) async {
    // 转换为批量上传
    final result = await uploadImages([imageInfo], provider);
    return result.isNotEmpty;
  }

  /// 下载缺失的图片文件（从历史记录数据中获取图片对象键）
  Future<void> downloadMissingImages(
    List<ImageFileInfo> requiredImages,
    SyncProvider provider,
    Map<String, dynamic> historyData,
  ) async {
    if (requiredImages.isEmpty) {
      return;
    }
    
    try {
      print('[ImageSync] 开始从历史记录数据中提取图片对象键');
      
      // 从历史记录数据中收集所有图片对象键
      final Map<String, String> imagePathToObjectKey = {};
      final sessions = historyData['sessions'] as List<dynamic>? ?? [];
      
      for (final session in sessions) {
        final sessionMap = session as Map<String, dynamic>;
        final results = sessionMap['results'] as List<dynamic>? ?? [];
        
        for (final result in results) {
          final resultMap = result as Map<String, dynamic>;
          
          // 收集原始图片对象键
          final originalPath = resultMap['original_image_path'] as String?;
          final originalObjectKey = resultMap['original_image_object_key'] as String?;
          if (originalPath != null && originalObjectKey != null) {
            imagePathToObjectKey[originalPath] = originalObjectKey;
          }
          
          // 收集批改图片对象键
          final annotatedPath = resultMap['annotated_image_path'] as String?;
          final annotatedObjectKey = resultMap['annotated_image_object_key'] as String?;
          if (annotatedPath != null && annotatedObjectKey != null) {
            imagePathToObjectKey[annotatedPath] = annotatedObjectKey;
          }
        }
      }
      
      print('[ImageSync] 从历史记录中找到 ${imagePathToObjectKey.length} 个图片对象键');
      print('[ImageSync] 需要下载的图片数量: ${requiredImages.length}');
      
      // 下载每个需要的图片文件
      for (final requiredImage in requiredImages) {
        try {
          print('[ImageSync] 正在下载图片: ${requiredImage.relativePath}');
          await _downloadSingleImageFromObjectKey(requiredImage, imagePathToObjectKey, provider);
        } catch (e) {
          print('[ImageSync] 下载图片失败: ${requiredImage.relativePath}, $e');
        }
      }
      print('[ImageSync] 图片下载完成');
    } catch (e) {
      print('[ImageSync] 下载图片过程中出错: $e');
    }
  }

  /// 从对象键下载单个图片文件
  Future<void> _downloadSingleImageFromObjectKey(
    ImageFileInfo imageInfo,
    Map<String, String> imagePathToObjectKey,
    SyncProvider provider,
  ) async {
    final localPath = path.join(_appDocDir.path, imageInfo.relativePath);
    final file = File(localPath);
    
    // 如果本地文件已存在且哈希匹配，跳过下载
    if (await file.exists()) {
      final localHash = _calculateFileHash(file);
      if (localHash == imageInfo.hash) {
        print('[ImageSync] 本地文件已存在且哈希匹配，跳过下载: ${imageInfo.relativePath}');
        return;
      }
    }
    
    // 查找对应的对象键
    final objectKey = imagePathToObjectKey[imageInfo.relativePath];
    if (objectKey == null) {
      print('[ImageSync] 未找到图片对象键: ${imageInfo.relativePath}');
      return;
    }
    
    try {
      // 直接从对象存储下载图片
      final downloadResult = await provider.downloadImageByObjectKey(objectKey);
      if (!downloadResult.success || downloadResult.data == null) {
        print('[ImageSync] 下载图片失败: $objectKey, ${downloadResult.message}');
        return;
      }
      
      final bytes = downloadResult.data!['content'] as List<int>;
      
      // 确保目录存在
      final dir = Directory(path.dirname(localPath));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      
      // 写入文件
      await file.writeAsBytes(bytes);
      
      // 验证下载的文件哈希
      final downloadedHash = _calculateFileHash(file);
      if (downloadedHash == imageInfo.hash) {
        print('[ImageSync] 图片下载成功: ${imageInfo.relativePath}');
      } else {
        print('[ImageSync] 图片下载后哈希不匹配: ${imageInfo.relativePath}');
        await file.delete(); // 删除损坏的文件
      }
    } catch (e) {
      print('[ImageSync] 保存图片文件失败: ${imageInfo.relativePath}, $e');
    }
  }

  /// 从下载的图片数据中保存单个图片文件（已弃用）
  @deprecated
  Future<void> _downloadSingleImageFromData(
    ImageFileInfo imageInfo,
    Map<String, Map<String, dynamic>> imageMap,
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
    
    // 从图片数据映射中查找对应的图片
    final imageData = imageMap[imageInfo.hash];
    if (imageData == null) {
      print('未找到图片数据: ${imageInfo.hash}');
      return;
    }
    
    final bytes = imageData['bytes'] as List<int>?;
    if (bytes == null) {
      print('图片数据为空: ${imageInfo.hash}');
      return;
    }
    
    try {
      // 确保目录存在
      final dir = Directory(path.dirname(localPath));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      
      // 写入文件
      await file.writeAsBytes(bytes);
      
      // 验证下载的文件哈希
      final downloadedHash = _calculateFileHash(file);
      if (downloadedHash == imageInfo.hash) {
        print('图片下载成功: ${imageInfo.relativePath}');
      } else {
        print('图片下载后哈希不匹配: ${imageInfo.relativePath}');
        await file.delete(); // 删除损坏的文件
      }
    } catch (e) {
      print('保存图片文件失败: ${imageInfo.relativePath}, $e');
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