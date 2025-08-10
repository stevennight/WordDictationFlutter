import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// 路径转换工具类
/// 提供统一的相对路径和绝对路径转换功能
class PathUtils {
  static Directory? _cachedAppDir;
  
  /// 获取应用程序根目录
  /// 桌面平台使用可执行文件目录，移动平台使用文档目录
  static Future<Directory> getAppDirectory() async {
    if (_cachedAppDir != null) {
      return _cachedAppDir!;
    }
    
    String appDirPath;
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      // 桌面平台：使用可执行文件目录
      final executablePath = Platform.resolvedExecutable;
      appDirPath = path.dirname(executablePath);
    } else {
      // 移动平台：使用文档目录
      final appDocDir = await getApplicationDocumentsDirectory();
      appDirPath = appDocDir.path;
    }
    
    _cachedAppDir = Directory(appDirPath);
    return _cachedAppDir!;
  }
  
  /// 将绝对路径转换为相对于应用程序目录的相对路径
  /// 返回使用正斜杠的跨平台兼容路径
  /// 
  /// [absolutePath] 要转换的绝对路径
  /// 返回相对路径字符串，使用正斜杠分隔符
  static Future<String> convertToRelativePath(String absolutePath) async {
    try {
      final appDir = await getAppDirectory();
      final relativePath = path.relative(absolutePath, from: appDir.path);
      // 转换为使用正斜杠的跨平台兼容路径
      return relativePath.replaceAll('\\', '/');
    } catch (e) {
      debugPrint('转换相对路径失败: $e');
      // 如果转换失败，返回原路径
      return absolutePath;
    }
  }
  
  /// 将相对路径转换为绝对路径
  /// 处理数据库中存储的正斜杠路径，转换为系统适配的绝对路径
  /// 
  /// [relativePath] 要转换的相对路径
  /// 返回系统适配的绝对路径
  static Future<String> convertToAbsolutePath(String relativePath) async {
    try {
      // 如果已经是绝对路径，直接返回
      if (path.isAbsolute(relativePath)) {
        return relativePath;
      }
      
      final appDir = await getAppDirectory();
      
      // 将数据库中的正斜杠路径转换为系统路径分隔符
      // 使用path.joinAll来处理路径片段，确保使用正确的系统分隔符
      final pathSegments = relativePath.split('/');
      final absolutePath = path.joinAll([appDir.path, ...pathSegments]);
      
      if (kDebugMode) {
        debugPrint('Path conversion: $relativePath -> $absolutePath (appDir: ${appDir.path})');
      }
      
      return absolutePath;
    } catch (e) {
      debugPrint('转换绝对路径失败: $e');
      // 如果转换失败，返回原路径
      return relativePath;
    }
  }
  
  /// 根据路径获取File对象，自动处理相对路径和绝对路径
  /// 
  /// [filePath] 文件路径，可以是相对路径或绝对路径
  /// 返回File对象，如果路径转换失败则返回null
  static Future<File?> getFile(String filePath) async {
    try {
      String absolutePath;
      if (path.isAbsolute(filePath)) {
        absolutePath = filePath;
      } else {
        absolutePath = await convertToAbsolutePath(filePath);
      }
      return File(absolutePath);
    } catch (e) {
      debugPrint('获取文件失败: $e');
      return null;
    }
  }
  
  /// 清除缓存的应用程序目录
  /// 主要用于测试或特殊情况下需要重新获取目录
  static void clearCache() {
    _cachedAppDir = null;
  }
}