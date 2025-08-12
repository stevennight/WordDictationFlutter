# Flutter Word Dictation App

Version 1.1.1-pre
（Preview版本，有可能造成数据损坏或丢失，暂未经过充分测试，请谨慎使用）

基于原Python版本wordDictation默写工具的Flutter跨平台实现

## 功能特性

### 核心功能
- 📝 **手写默写**: 支持触屏手写输入，模拟真实默写体验
- 📄 **文件导入**: 支持Excel(.xlsx)、CSV(.csv)和JSON格式的单词表导入
  - ✅ **Excel兼容性**: 完全支持WPS Office生成的Excel文件
  - 🔧 **智能修复**: 自动处理非标准格式问题（numFmtId兼容性）
  - 📊 **多种格式**: 支持标准Excel、WPS Excel、CSV等多种格式
- 🔀 **多种默写模式**: 顺序默写、乱序默写、自定义数量
- ✅ **智能批改**: 手动判断正误，支持批注功能
- 📊 **统计分析**: 详细的正确率统计和错题分析
- 📚 **历史记录**: 完整的默写历史保存和回顾
- 🔄 **错题重做**: 针对错题进行专项练习
- ☁️ **云同步功能**: 支持多种云存储服务的数据同步
  - 🔄 **自动同步**: 应用启动、关闭和定时自动同步
  - 🗂️ **智能备份**: 自动管理备份文件，保留指定数量的历史版本
  - 🔧 **多配置支持**: 支持多个同步配置，灵活管理不同存储服务
- 🎨 **主题切换**: 支持明暗主题切换
- 📱 **跨平台**: 支持Android、iOS、Windows、macOS、Linux

### 技术特性
- 🎯 **响应式设计**: 适配不同屏幕尺寸
- 💾 **本地存储**: 使用SQLite数据库存储数据
- 🖼️ **图片缓存**: 手写内容自动保存为图片
- ⚙️ **配置管理**: 个性化设置持久化
- 🔧 **模块化架构**: 清晰的代码结构和组件分离
- 📁 **文件兼容性**: 智能处理各种Office软件生成的文件
- 🛠️ **错误恢复**: 多重解码策略确保文件导入成功率
- ☁️ **云存储集成**: 支持阿里云OSS、AWS S3等对象存储服务
- 🔄 **智能同步**: 应用生命周期感知的自动同步机制
- 🗂️ **备份管理**: 自动清理旧备份文件，优化存储空间
- 🔍 **调试优化**: 简洁的日志输出，提升用户体验

## 项目结构

```
flutter_word_dictation/
├── lib/
│   ├── main.dart                 # 应用入口
│   ├── app.dart                  # 应用主体
│   ├── core/                     # 核心功能
│   │   ├── constants/            # 常量定义
│   │   ├── database/             # 数据库相关
│   │   ├── services/             # 业务服务
│   │   └── utils/                # 工具函数
│   ├── features/                 # 功能模块
│   │   ├── dictation/            # 默写功能
│   │   ├── history/              # 历史记录
│   │   ├── settings/             # 设置功能
│   │   ├── sync/                 # 云同步功能
│   │   └── wordbook/             # 单词本管理
│   ├── shared/                   # 共享组件
│   │   ├── widgets/              # 通用组件
│   │   ├── models/               # 数据模型
│   │   └── providers/            # 状态管理
│   └── theme/                    # 主题配置
├── assets/                       # 资源文件
│   ├── images/                   # 图片资源
│   └── fonts/                    # 字体文件
├── test/                         # 测试文件
├── android/                      # Android平台配置
├── ios/                          # iOS平台配置
├── windows/                      # Windows平台配置
├── macos/                        # macOS平台配置
├── linux/                        # Linux平台配置
└── web/                          # Web平台配置
```

## 核心模块设计

### 1. 数据模型
- **Word**: 单词数据模型（提示词、答案）
- **DictationSession**: 默写会话模型
- **DictationResult**: 默写结果模型
- **HistoryRecord**: 历史记录模型
- **AppConfig**: 应用配置模型

### 2. 数据库设计
- **words**: 单词表
- **dictation_sessions**: 默写会话表
- **dictation_results**: 默写结果表
- **history_records**: 历史记录表
- **app_settings**: 应用设置表

### 3. 核心服务
- **WordImportService**: 单词导入服务
- **DictationService**: 默写业务服务
- **HistoryService**: 历史记录服务
- **ConfigService**: 配置管理服务
- **FileService**: 文件操作服务
- **SyncService**: 云同步核心服务
- **AutoSyncManager**: 自动同步管理器
- **ObjectStorageSyncProvider**: 对象存储同步提供者

### 4. 主要界面
- **HomeScreen**: 主页面（文件导入、模式选择）
- **DictationScreen**: 默写界面（手写画布、工具栏）
- **CorrectionScreen**: 批改界面（答案显示、批注）
- **SummaryScreen**: 结果总结界面
- **HistoryScreen**: 历史记录界面
- **SettingsScreen**: 设置界面
- **SyncSettingsScreen**: 同步设置界面
- **ObjectStorageConfigDialog**: 对象存储配置对话框

## 技术栈

- **Flutter**: 3.16+
- **Dart**: 3.2+
- **状态管理**: Provider / Riverpod
- **数据库**: SQLite (sqflite)
- **文件处理**: file_picker, path_provider
- **手写画布**: CustomPainter
- **主题**: Material Design 3
- **国际化**: flutter_localizations

## 开发进度

### ✅ 已完成功能
- [x] 项目初始化和结构搭建
- [x] 数据库设计和实现
- [x] 基础模型定义
- [x] 核心服务框架
- [x] 单词导入功能（Excel/CSV/JSON）
- [x] WPS Office文件兼容性修复
- [x] 手写画布组件
- [x] 默写流程实现
- [x] 结果统计功能
- [x] 历史记录管理
- [x] 错题重做功能
- [x] 设置和配置
- [x] 主题切换
- [x] 云同步功能（阿里云OSS、AWS S3）
- [x] 自动同步机制（启动/关闭/定时）
- [x] 智能备份管理和清理
- [x] 多同步配置支持
- [x] 调试日志优化

### 🚧 开发中
- [ ] 性能优化
- [ ] UI/UX改进
- [ ] 多平台适配测试

### 📋 计划中
- [ ] 多语言支持
- [ ] 语音播放功能
- [ ] 单词本分类管理
- [ ] 学习进度统计
- [ ] 云同步功能增强（更多存储服务支持）
- [ ] 同步冲突解决机制优化

## 文件兼容性说明

### 支持的文件格式
- **Excel文件 (.xlsx)**: 支持Microsoft Excel和WPS Office生成的文件
- **CSV文件 (.csv)**: 标准逗号分隔值文件
- **JSON文件 (.json)**: 自定义JSON格式单词数据

### WPS Office兼容性
本应用已完全解决WPS Office生成的Excel文件兼容性问题：
- 自动修复非标准数字格式定义（numFmtId问题）
- 智能处理ZIP文件结构差异
- 多重解码策略确保文件读取成功

### 推荐文件格式
1. **Excel格式**: 支持完整的单词信息（单词、词性、含义、等级）
2. **CSV格式**: 简单可靠，兼容性最佳
3. **JSON格式**: 适合程序化生成的数据

## 云同步功能说明

### 支持的存储服务
- **阿里云对象存储 OSS**: 完整支持，包括自定义域名和SSL
- **AWS S3**: 兼容S3协议的对象存储服务
- **其他S3兼容服务**: 支持自定义端点的S3兼容存储

### 同步特性
- **智能触发**: 应用启动时、关闭时和定时自动同步
- **增量同步**: 只同步有变化的数据，节省流量和时间
- **备份管理**: 自动保留指定数量的历史备份，定期清理旧文件
- **冲突处理**: 智能合并本地和云端数据，避免数据丢失
- **多配置支持**: 可配置多个同步服务，灵活管理不同存储

### 同步内容
- **历史记录数据**: 默写会话、结果和统计信息
- **手写图片**: 默写过程中的手写内容图片
- **配置信息**: 应用设置和个性化配置

### 使用建议
1. **同步间隔**: 建议设置为1-6小时，平衡数据安全和电量消耗
2. **备份数量**: 建议保留1-5个备份版本，根据存储空间调整
3. **网络环境**: 在WiFi环境下进行大量数据同步，节省流量

## 安装和运行

```bash
# 克隆项目
git clone <repository-url>
cd flutter_word_dictation

# 安装依赖
flutter pub get

# 运行应用
flutter run

# 构建发布版本
flutter build apk  # Android
flutter build ios  # iOS
flutter build windows  # Windows
```

## 贡献指南

1. Fork 项目
2. 创建功能分支 (`git checkout -b feature/AmazingFeature`)
3. 提交更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 打开 Pull Request

## 许可证

本项目采用 MIT 许可证 - 查看 [LICENSE](LICENSE) 文件了解详情。