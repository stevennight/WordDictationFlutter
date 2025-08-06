# GitHub Actions 自动构建系统

本项目已配置完整的GitHub Actions自动构建系统，可以自动构建Windows和Android版本，并发布到GitHub Releases。

## 🚀 功能特性

- ✅ 自动构建Windows版本（.exe + 依赖文件打包为.zip）
- ✅ 自动构建Android版本（APK + AAB文件）
- ✅ 自动创建GitHub Release并上传构建文件
- ✅ 支持手动触发构建
- ✅ 代码质量检查（测试、分析、格式化）
- ✅ 灵活的构建选项

## 📋 工作流程列表

### 1. 🏷️ 自动构建和发布 (`build-and-release.yml`)
**触发方式：**
- 推送版本标签（如 `v1.0.0`）
- 手动触发

**功能：**
- 构建Windows和Android版本
- 自动创建GitHub Release（仅限标签推送）

### 2. 🔧 手动构建 (`manual-build.yml`)
**触发方式：**
- 仅手动触发

**功能：**
- 可选择性构建Windows/Android版本
- 可选择性创建Release
- 自定义Release标签

### 3. 🧪 测试构建 (`test-build.yml`)
**触发方式：**
- Pull Request到main/master分支
- 推送到main/master分支
- 手动触发

**功能：**
- 代码质量检查
- 测试构建（不生成发布文件）

## 🎯 快速开始

### 方法1：自动发布（推荐）
```bash
# 1. 更新版本号（在pubspec.yaml中）
# 2. 提交更改
git add .
git commit -m "Release v1.0.1"

# 3. 创建并推送标签
git tag v1.0.1
git push origin v1.0.1

# 4. GitHub Actions会自动构建并创建Release
```

### 方法2：手动构建
1. 进入GitHub仓库页面
2. 点击 **Actions** 标签
3. 选择 **Manual Build** 工作流程
4. 点击 **Run workflow**
5. 配置构建选项并运行

## 📦 构建产物

| 平台 | 文件名 | 说明 |
|------|--------|------|
| Windows | `flutter_word_dictation_windows.zip` | 包含.exe和所有依赖文件 |
| Android | `app-release.apk` | 用于直接安装 |
| Android | `app-release.aab` | 用于Google Play Store |

## ⚙️ 技术规格

- **Flutter版本：** 3.16.0
- **Java版本：** 17（Android构建）
- **构建环境：**
  - Windows: `windows-latest`
  - Android: `ubuntu-latest`
- **文件保留期：** 30天

## 🔍 使用说明

### 查看构建状态
1. 进入仓库的 **Actions** 页面
2. 查看最近的工作流程运行状态
3. 点击具体运行查看详细日志

### 下载构建文件
**方法1：从GitHub Release下载**
- 进入仓库的 **Releases** 页面
- 下载最新版本的构建文件

**方法2：从Actions Artifacts下载**
- 进入具体的工作流程运行页面
- 在 **Artifacts** 部分下载构建文件

## 🛠️ 自定义配置

如需修改构建配置，编辑以下文件：
- `.github/workflows/build-and-release.yml`
- `.github/workflows/manual-build.yml`
- `.github/workflows/test-build.yml`

常见修改：
- 更改Flutter版本
- 调整构建参数
- 修改文件命名
- 添加构建步骤

## 📚 详细文档

查看 `.github/ACTIONS_GUIDE.md` 获取更详细的使用指南和故障排除信息。

## ⚠️ 注意事项

1. **首次使用**：确保仓库有创建Release的权限
2. **版本标签**：使用语义化版本（如v1.0.0）
3. **构建时间**：完整构建需要10-20分钟
4. **存储限制**：注意GitHub Actions的使用配额

---

🎉 现在你可以享受自动化构建和发布的便利了！