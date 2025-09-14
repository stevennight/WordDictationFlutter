import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

/// 文件哈希工具类
class FileHashUtils {
  /// 计算文件的MD5哈希值
  static String calculateFileMd5(File file) {
    if (!file.existsSync()) {
      throw FileSystemException('文件不存在', file.path);
    }
    
    final bytes = file.readAsBytesSync();
    final digest = md5.convert(bytes);
    return digest.toString();
  }
  
  /// 异步计算文件的MD5哈希值
  static Future<String> calculateFileMd5Async(File file) async {
    if (!await file.exists()) {
      throw FileSystemException('文件不存在', file.path);
    }
    
    final bytes = await file.readAsBytes();
    final digest = md5.convert(bytes);
    return digest.toString();
  }
  
  /// 计算字节数组的MD5哈希值
  static String calculateBytesMd5(Uint8List bytes) {
    final digest = md5.convert(bytes);
    return digest.toString();
  }
  
  /// 检查本地文件是否需要从远端下载（基于MD5比较）
  /// 
  /// 当以下情况时返回true：
  /// - 远端MD5为空或null（远端文件不存在）
  /// - 本地文件不存在
  /// - 本地文件MD5与远端MD5不匹配
  /// - MD5计算失败
  static Future<bool> needsDownload(String localPath, String? remoteMd5) async {
    if (remoteMd5 == null || remoteMd5.isEmpty) {
      return true; // 远端没有MD5，需要下载
    }
    
    final localFile = File(localPath);
    if (!await localFile.exists()) {
      return true; // 本地文件不存在，需要下载
    }
    
    try {
      final localMd5 = await calculateFileMd5Async(localFile);
      return localMd5 != remoteMd5; // MD5不同则需要下载
    } catch (e) {
      return true; // 计算失败，保险起见认为需要下载
    }
  }
  
  /// 生成基于原始文件名和MD5的云端对象键
  static String generateCloudObjectKey(String originalPath, String md5Hash) {
    return originalPath;
  }
}