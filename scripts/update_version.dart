#!/usr/bin/env dart

/// 版本号更新脚本
/// 用法: dart scripts/update_version.dart <version> [build_number]
/// 例如: dart scripts/update_version.dart 1.1.0-pre 1

import 'dart:io';

void main(List<String> args) {
  if (args.isEmpty) {
    print('用法: dart scripts/update_version.dart <version> [build_number]');
    print('例如: dart scripts/update_version.dart 1.1.0-pre 1');
    exit(1);
  }

  final version = args[0];
  final buildNumber = args.length > 1 ? int.tryParse(args[1]) ?? 1 : 1;

  print('更新版本号到: $version+$buildNumber');

  // 更新 pubspec.yaml
  updatePubspecYaml(version, buildNumber);

  // 更新 AppVersion 配置
  updateAppVersionConfig(version, buildNumber);

  // 更新 README.md
  updateReadme(version);

  print('版本号更新完成！');
  print('请记得提交这些更改到版本控制系统。');
}

void updatePubspecYaml(String version, int buildNumber) {
  final file = File('pubspec.yaml');
  if (!file.existsSync()) {
    print('错误: 找不到 pubspec.yaml 文件');
    exit(1);
  }

  final content = file.readAsStringSync();
  final updatedContent = content.replaceAll(
    RegExp(r'^version: .*', multiLine: true),
    'version: $version+$buildNumber',
  );

  file.writeAsStringSync(updatedContent);
  print('✓ 已更新 pubspec.yaml');
}

void updateAppVersionConfig(String version, int buildNumber) {
  final file = File('lib/core/config/app_version.dart');
  if (!file.existsSync()) {
    print('错误: 找不到 app_version.dart 文件');
    exit(1);
  }

  final content = '''
/// 应用版本配置
/// 统一管理应用版本号，避免在多个地方重复定义
class AppVersion {
  /// 应用版本号
  /// 格式：major.minor.patch[-prerelease]
  static const String version = '$version';
  
  /// 构建号
  /// 用于区分同一版本的不同构建
  static const int buildNumber = $buildNumber;
  
  /// 完整版本字符串
  /// 格式：version+buildNumber
  static const String fullVersion = '\$version+\$buildNumber';
  
  /// 获取版本信息的显示字符串
  static String get displayVersion => version;
  
  /// 获取完整版本信息
  static String get fullVersionString => fullVersion;
}
''';

  file.writeAsStringSync(content);
  print('✓ 已更新 app_version.dart');
}

void updateReadme(String version) {
  final file = File('README.md');
  if (!file.existsSync()) {
    print('警告: 找不到 README.md 文件');
    return;
  }

  final content = file.readAsStringSync();
  final updatedContent = content.replaceAll(
    RegExp(r'^Version .*', multiLine: true),
    'Version $version',
  );

  file.writeAsStringSync(updatedContent);
  print('✓ 已更新 README.md');
}