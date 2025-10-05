# 版本号管理指南

本项目采用统一的版本号管理方案，避免在多个文件中重复维护版本信息。

## 版本号格式

遵循 [Semantic Versioning](https://semver.org/) 规范：

```
<major>.<minor>.<patch>[-prerelease][+build]
```

- **major**: 主版本号，不兼容的API修改
- **minor**: 次版本号，向下兼容的功能性新增
- **patch**: 修订号，向下兼容的问题修正
- **prerelease**: 预发布版本标识（可选），如 `alpha`, `beta`, `rc`, `pre`
- **build**: 构建号（可选），用于区分同一版本的不同构建

## 版本号存储位置

### 主要配置文件

1. **`pubspec.yaml`** - Flutter项目的主要版本定义
   ```yaml
   version: 1.1.0-pre+1
   ```

2. **`lib/core/config/app_version.dart`** - 应用内版本配置
   ```dart
   class AppVersion {
     static const String version = '1.1.0-pre';
     static const int buildNumber = 1;
   }
   ```

3. **`README.md`** - 项目文档中的版本信息
   ```markdown
   Version 1.1.0-pre
   ```

### 自动同步的文件

以下文件会从 `pubspec.yaml` 或 `AppVersion` 自动获取版本信息：

- `android/app/build.gradle.kts` - Android构建配置
- `lib/features/settings/screens/settings_screen.dart` - 设置页面
- `lib/features/settings/widgets/about_dialog.dart` - 关于对话框
- `lib/app.dart` - 应用主文件

## 版本更新方法

### 方法一：使用自动化脚本（推荐）

```bash
# Windows
update_version.bat 1.1.0-pre 1

# 或直接使用 Dart 脚本
dart scripts/update_version.dart 1.1.0-pre 1
```

脚本会自动更新以下文件：
- `pubspec.yaml`
- `lib/core/config/app_version.dart`
- `README.md`

### 方法二：手动更新

1. 更新 `pubspec.yaml` 中的 `version` 字段
2. 更新 `lib/core/config/app_version.dart` 中的版本常量
3. 更新 `README.md` 中的版本信息
4. 确保所有引用 `AppVersion` 的代码都能正确获取新版本

## 版本发布流程

1. **开发阶段**: 使用预发布版本，如 `1.1.0-pre`, `1.1.0-alpha`, `1.1.0-beta`
2. **测试阶段**: 使用候选版本，如 `1.1.0-rc.1`, `1.1.0-rc.2`
3. **正式发布**: 使用正式版本，如 `1.1.0`
4. **热修复**: 使用修订版本，如 `1.1.1`, `1.1.2`

## 注意事项

1. **保持一致性**: 确保所有配置文件中的版本号保持一致
2. **使用脚本**: 推荐使用自动化脚本更新版本，减少人为错误
3. **版本控制**: 每次版本更新后及时提交到版本控制系统
4. **构建号**: Android 和 iOS 平台会自动从 `pubspec.yaml` 获取构建号
5. **预发布标识**: 预发布版本不会被应用商店视为正式版本

## 示例

```bash
# 开发版本
dart scripts/update_version.dart 1.2.0-dev 1

# 测试版本
dart scripts/update_version.dart 1.2.0-beta 1

# 候选版本
dart scripts/update_version.dart 1.2.0-rc.1 1

# 正式版本
dart scripts/update_version.dart 1.2.0 1

# 热修复版本
dart scripts/update_version.dart 1.2.1 1
```

通过这种统一的版本管理方案，可以确保整个项目的版本信息保持一致，并简化版本更新流程。