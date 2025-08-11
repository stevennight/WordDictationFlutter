import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path/path.dart' show dirname;
import 'package:path_provider/path_provider.dart';

import '../../shared/utils/path_utils.dart';
import '../utils/file_hash_utils.dart';
import 'history_sync_service.dart';
import 'sync_service.dart';

/// 图片同步管理器
/// 负责处理历史记录中的笔迹图片文件的上传下载和去重
class HistoryFileSyncManager {
  static final HistoryFileSyncManager _instance = HistoryFileSyncManager._internal();
  factory HistoryFileSyncManager() => _instance;
  HistoryFileSyncManager._internal();

  late Directory _appDocDir;
  late Directory _syncCacheDir;
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
    
    // 初始化sync_cache目录
    _syncCacheDir = Directory(path.join(_appDocDir.path, 'sync_cache'));
    if (!await _syncCacheDir.exists()) {
      await _syncCacheDir.create(recursive: true);
    }
    
    // 将图片缓存目录放到sync_cache下
    _imagesCacheDir = Directory(path.join(_syncCacheDir.path, 'handwriting_cache'));
    
    // 确保缓存目录存在
    if (!await _imagesCacheDir.exists()) {
      await _imagesCacheDir.create(recursive: true);
    }
  }

  /// 下载缺失的图片文件（直接从历史记录数据中获取图片信息）
  Future<void> downloadMissingImages(
    List<ImageFileInfo> requiredImages, // 保持参数兼容性，但实际不使用
    SyncProvider provider,
    Map<String, dynamic> historyData, {
    void Function(String step, {int? current, int? total})? onProgress,
  }) async {
    try {
      print('[ImageSync] 开始从历史记录数据中提取图片信息');
      
      // 从历史记录数据中收集所有图片信息
      final Map<String, String> imagePathToObjectKey = {};
      final Map<String, String> imagePathToMd5 = {};
      final sessions = historyData['sessions'] as List<dynamic>? ?? [];
      
      for (final session in sessions) {
        final sessionMap = session as Map<String, dynamic>;
        final results = sessionMap['results'] as List<dynamic>? ?? [];
        
        for (final result in results) {
          final resultMap = result as Map<String, dynamic>;
          
          // 收集原始图片信息
          final originalPath = resultMap['original_image_path'] as String?;
          final originalMd5 = resultMap['original_image_md5'] as String?;
          if (originalPath != null && originalPath.isNotEmpty) {
            if (originalMd5 != null && originalMd5.isNotEmpty) {
              imagePathToMd5[originalPath] = originalMd5;
              
              // 使用相同的生成规则重新构建对象键
              final generatedObjectKey = FileHashUtils.generateCloudObjectKey(originalPath, originalMd5);
              imagePathToObjectKey[originalPath] = generatedObjectKey;
              print('[ImageSync] 生成原始图片对象键: $originalPath -> $generatedObjectKey');
            }
          }
      
          // 收集批改图片信息
          final annotatedPath = resultMap['annotated_image_path'] as String?;
          final annotatedMd5 = resultMap['annotated_image_md5'] as String?;
          if (annotatedPath != null && annotatedPath.isNotEmpty) {
            if (annotatedMd5 != null && annotatedMd5.isNotEmpty) {
              imagePathToMd5[annotatedPath] = annotatedMd5;
              
              // 使用相同的生成规则重新构建对象键
              final generatedObjectKey = FileHashUtils.generateCloudObjectKey(annotatedPath, annotatedMd5);
              imagePathToObjectKey[annotatedPath] = generatedObjectKey;
              print('[ImageSync] 生成批改图片对象键: $annotatedPath -> $generatedObjectKey');
            }
          }
        }
      }
      
      print('[ImageSync] 从历史记录中找到 ${imagePathToObjectKey.length} 个图片对象键');
      print('[ImageSync] 从历史记录中找到 ${imagePathToMd5.length} 个图片MD5');
      
      // 检查哪些图片需要下载（本地不存在或MD5不匹配）
      final List<String> imagesToDownload = [];
      for (final imagePath in imagePathToMd5.keys) {
        final absolutedImagePath = await PathUtils.convertToAbsolutePath(imagePath);
        final localFile = File(absolutedImagePath);
        final expectedMd5 = imagePathToMd5[imagePath]!;
        
        bool needDownload = false;
        if (!localFile.existsSync()) {
          print('[ImageSync] 本地文件不存在，需要下载: $absolutedImagePath');
          needDownload = true;
        } else {
          // 检查MD5是否匹配
          needDownload = await FileHashUtils.needsSync(absolutedImagePath, expectedMd5);
          print('[ImageSync] 根据文件MD5判断是否需要同步，是否同步:${needDownload.toString()}}');
        }
        
        if (needDownload) {
          imagesToDownload.add(imagePath);
        }
      }
      
      if (imagesToDownload.isEmpty) {
        print('[ImageSync] 没有需要下载的图片文件');
        return;
      }
      
      print('[ImageSync] 需要下载 ${imagesToDownload.length} 个图片文件');
      
      // 下载每个需要的图片文件
      int downloadedCount = 0;
      for (final imagePath in imagesToDownload) {
        try {
          onProgress?.call('正在下载图片: $imagePath', current: downloadedCount, total: imagesToDownload.length);
          print('[ImageSync] 正在下载图片: $imagePath');
          final absolutedImagePath = await PathUtils.convertToAbsolutePath(imagePath);
          final objectKey = imagePathToObjectKey[imagePath];
          if (objectKey == null) {
            throw '未找到图片对象键: $imagePath';
          }
          await _downloadSingleImageFromObjectKey(absolutedImagePath, objectKey, provider);
          
          downloadedCount++;

          // 使用Future.delayed代替sleep，避免阻塞UI线程
          await Future.delayed(const Duration(seconds: 5));
        } catch (e) {
          print('[ImageSync] 下载图片失败: $imagePath, $e');
          downloadedCount++; // 即使失败也要增加计数
        }
      }
      print('[ImageSync] 图片下载完成');
    } catch (e) {
      print('[ImageSync] 下载图片过程中出错: $e');
    }
  }

  /// 从对象键下载单个图片文件
  Future<void> _downloadSingleImageFromObjectKey(
    String imagePath,
    String objectKey,
    SyncProvider provider,
  ) async {
    final file = File(imagePath);
    
    print('[ImageSync] 开始下载图片: $imagePath, 对象键: $objectKey');
    
    try {
      // 直接从对象存储下载图片
      final downloadResult = await provider.downloadBytes(objectKey);
      if (!downloadResult.success || downloadResult.data == null) {
        print('[ImageSync] 下载图片失败: $objectKey, ${downloadResult.message}');
        return;
      }
      
      final bytes = downloadResult.data!['content'] as List<int>;
      
      // 确保目录存在
      final dir = Directory(path.dirname(imagePath));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      
      // 写入文件
      await file.writeAsBytes(bytes);
      
      print('[ImageSync] 图片下载成功: $imagePath -> $imagePath');
    } catch (e) {
      print('[ImageSync] 保存图片文件失败: $imagePath -> $imagePath, $e');
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
              // 使用公共路径工具类生成相对路径
              final relativePath = await PathUtils.convertToRelativePath(entity.path);
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

  /// 使用预先计算的MD5值获取图片文件信息，避免重复计算
  Future<ImageFileInfo?> getImageFileInfoWithMd5(String filePath, String md5Hash, bool ignoreFileNotExist) async {
    try {
      final file = File(filePath);
      if (!ignoreFileNotExist && !await file.exists()) {
        return null;
      }
      
      final stat = await file.stat();
      
      // 使用公共路径工具类计算相对路径
      final relativePath = await PathUtils.convertToRelativePath(filePath);
      
      return ImageFileInfo(
        relativePath: relativePath,
        hash: md5Hash, // 直接使用传入的MD5值
        size: stat.size,
        lastModified: stat.modified,
      );
    } catch (e) {
      print('获取图片文件信息失败: $filePath, $e');
      return null;
    }
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