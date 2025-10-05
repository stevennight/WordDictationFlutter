/// 应用版本配置
/// 统一管理应用版本号，避免在多个地方重复定义
class AppVersion {
  /// 应用版本号
  /// 格式：major.minor.patch[-prerelease]
  static const String version = '1.1.3';
  
  /// 构建号
  /// 用于区分同一版本的不同构建
  static const int buildNumber = 1;
  
  /// 完整版本字符串
  /// 格式：version+buildNumber
  static const String fullVersion = '$version+$buildNumber';
  
  /// 获取版本信息的显示字符串
  static String get displayVersion => version;
  
  /// 获取完整版本信息
  static String get fullVersionString => fullVersion;
}
