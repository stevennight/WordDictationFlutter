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
  
  /// 检查文件是否需要同步（基于MD5比较）
  static Future<bool> needsSync(String localPath, String? remoteMd5) async {
    if (remoteMd5 == null || remoteMd5.isEmpty) {
      return true; // 远端没有MD5，需要同步
    }
    
    final localFile = File(localPath);
    if (!await localFile.exists()) {
      return false; // 本地文件不存在，不需要同步
    }
    
    try {
      final localMd5 = await calculateFileMd5Async(localFile);
      return localMd5 != remoteMd5; // MD5不同则需要同步
    } catch (e) {
      return true; // 计算失败，保险起见认为需要同步
    }
  }
  
  /// 生成基于原始文件名和MD5的云端对象键
  static String generateCloudObjectKey(String originalPath, String md5Hash) {
    return originalPath;
  }
}