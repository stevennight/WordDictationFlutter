# GitHub Actions 自动构建指南

本项目配置了GitHub Actions来自动构建Windows和Android版本，并可选择性地创建GitHub Release。

## 工作流程说明

### 1. 自动构建和发布 (build-and-release.yml)

**触发条件：**
- 推送版本标签时（格式：v1.0.0, v2.1.3等）
- 手动触发

**功能：**
- 自动构建Windows版本（.zip压缩包）
- 自动构建Android版本（APK和AAB文件）
- 当推送版本标签时，自动创建GitHub Release并上传构建文件

**使用方法：**
```bash
# 创建并推送版本标签来触发自动发布
git tag v1.0.1
git push origin v1.0.1
```

### 2. 手动构建 (manual-build.yml)

**触发条件：**
- 仅手动触发

**功能：**
- 可选择性构建Windows版本
- 可选择性构建Android版本
- 可选择性创建GitHub Release
- 灵活的构建选项

**使用方法：**
1. 进入GitHub仓库页面
2. 点击 "Actions" 标签
3. 选择 "Manual Build" 工作流程
4. 点击 "Run workflow" 按钮
5. 配置构建选项：
   - Build Windows version: 是否构建Windows版本
   - Build Android version: 是否构建Android版本
   - Create GitHub Release: 是否创建Release
   - Release tag: 如果创建Release，指定标签名称

## 构建产物

### Windows版本
- **文件名：** `flutter_word_dictation_windows.zip`
- **内容：** 包含所有Windows运行所需的文件
- **使用：** 解压后直接运行 `flutter_word_dictation.exe`

### Android版本
- **APK文件：** `app-release.apk` - 用于直接安装
- **AAB文件：** `app-release.aab` - 用于Google Play Store发布

## 环境要求

- **Flutter版本：** 3.16.0
- **Java版本：** 17 (用于Android构建)
- **操作系统：** 
  - Windows构建：Windows Latest
  - Android构建：Ubuntu Latest

## 注意事项

1. **权限要求：** 确保仓库有足够的权限来创建Release和上传文件
2. **构建时间：** 完整构建可能需要10-20分钟
3. **存储限制：** 构建产物会保留30天
4. **版本标签：** 使用语义化版本标签（如v1.0.0）来触发自动发布

## 故障排除

### 常见问题

1. **构建失败**
   - 检查Flutter版本兼容性
   - 确保所有依赖都在pubspec.yaml中正确声明
   - 查看构建日志中的具体错误信息

2. **Release创建失败**
   - 确保有GITHUB_TOKEN权限
   - 检查标签名称格式是否正确
   - 确保标签不与现有Release冲突

3. **Android构建失败**
   - 检查Java版本兼容性
   - 确保Android配置文件正确

### 查看构建日志

1. 进入GitHub仓库的Actions页面
2. 选择相应的工作流程运行
3. 点击具体的作业查看详细日志

## 自定义配置

如需修改构建配置，可以编辑以下文件：
- `.github/workflows/build-and-release.yml` - 自动构建配置
- `.github/workflows/manual-build.yml` - 手动构建配置

常见的自定义选项：
- 修改Flutter版本
- 调整构建参数
- 更改文件命名规则
- 添加额外的构建步骤