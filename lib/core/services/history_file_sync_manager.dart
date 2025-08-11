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

  /// 使用预先计算的MD5值获取图片文件信息，避免重复计算
  Future<ImageFileInfo?> getImageFileInfoWithMd5(String filePath, String md5Hash, bool ignoreFileNotExist) async {
    try {
      final file = File(filePath);
      if (!ignoreFileNotExist && !await file.exists()) {
        return null;
      }
      
      final stat = await file.stat();
      
      return ImageFileInfo(
        filePath: filePath,
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