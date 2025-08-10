import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:path/path.dart' show dirname;
import 'package:path_provider/path_provider.dart';

/// 设备ID管理服务
/// 负责生成和管理全局唯一的设备ID
class DeviceIdService {
  static final DeviceIdService _instance = DeviceIdService._internal();
  factory DeviceIdService() => _instance;
  DeviceIdService._internal();

  static const String _deviceIdFileName = 'device_id.txt';
  String? _cachedDeviceId;
  late Directory _appRootDir;

  /// 初始化服务
  Future<void> initialize() async {
    // 获取应用根目录
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      // 桌面平台使用可执行文件目录
      final executablePath = Platform.resolvedExecutable;
      _appRootDir = Directory(dirname(executablePath));
    } else {
      // 移动平台使用应用文档目录
      _appRootDir = await getApplicationDocumentsDirectory();
    }
  }

  /// 获取设备ID文件路径
  String get _deviceIdFilePath => path.join(_appRootDir.path, _deviceIdFileName);

  /// 获取或创建设备ID
  /// 设备ID由以下部分组成以确保全局唯一性：
  /// 1. 时间戳（毫秒）
  /// 2. 应用路径的哈希值（确保同一电脑不同位置的应用有不同ID）
  /// 3. 随机数（进一步降低冲突概率）
  Future<String> getDeviceId() async {
    if (_cachedDeviceId != null) {
      return _cachedDeviceId!;
    }

    final file = File(_deviceIdFilePath);
    if (await file.exists()) {
      _cachedDeviceId = (await file.readAsString()).trim();
      return _cachedDeviceId!;
    } else {
      _cachedDeviceId = await _generateDeviceId();
      await file.writeAsString(_cachedDeviceId!);
      return _cachedDeviceId!;
    }
  }

  /// 生成新的设备ID
  Future<String> _generateDeviceId() async {
    // 1. 获取当前时间戳（毫秒）
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    
    // 2. 获取应用路径的哈希值
    final appPathBytes = utf8.encode(_appRootDir.path.toLowerCase());
    final appPathHash = sha256.convert(appPathBytes).toString().substring(0, 8);
    
    // 3. 生成随机数
    final random = DateTime.now().microsecond % 10000;
    
    // 4. 组合生成最终的设备ID
    final deviceId = '${timestamp}_${appPathHash}_$random';
    
    return deviceId;
  }

  /// 重新生成设备ID（用于测试或特殊情况）
  Future<String> regenerateDeviceId() async {
    final file = File(_deviceIdFilePath);
    if (await file.exists()) {
      await file.delete();
    }
    _cachedDeviceId = null;
    return await getDeviceId();
  }

  /// 检查设备ID文件是否存在
  Future<bool> deviceIdExists() async {
    final file = File(_deviceIdFilePath);
    return await file.exists();
  }

  /// 获取设备ID文件信息
  Future<Map<String, dynamic>> getDeviceIdInfo() async {
    final deviceId = await getDeviceId();
    final file = File(_deviceIdFilePath);
    final stat = await file.stat();
    
    return {
      'deviceId': deviceId,
      'filePath': _deviceIdFilePath,
      'created': stat.changed,
      'appRootDir': _appRootDir.path,
    };
  }
}