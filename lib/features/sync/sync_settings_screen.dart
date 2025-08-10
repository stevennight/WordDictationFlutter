import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/services/sync_service.dart';
import '../../shared/providers/history_provider.dart';
import 'widgets/object_storage_config_dialog.dart';
import 'widgets/sync_status_card.dart';
import 'widgets/sync_progress_dialog.dart';

class SyncSettingsScreen extends StatefulWidget {
  const SyncSettingsScreen({super.key});

  @override
  State<SyncSettingsScreen> createState() => _SyncSettingsScreenState();
}

class _SyncSettingsScreenState extends State<SyncSettingsScreen> {
  final SyncService _syncService = SyncService();
  bool _isLoading = false;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _initializeService();
  }

  Future<void> _initializeService() async {
    await _syncService.ensureInitialized();
    if (mounted) {
      setState(() {
        _initialized = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('同步设置'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _showAddSyncConfigDialog,
            tooltip: '添加同步配置',
          ),
        ],
      ),
      body: _initialized ? _buildBody() : const Center(child: CircularProgressIndicator()),
    );
  }

  Widget _buildBody() {
    final configs = _syncService.configs;
    
    if (configs.isEmpty) {
      return _buildEmptyState();
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: configs.length,
      itemBuilder: (context, index) {
        final config = configs[index];
        return SyncStatusCard(
          config: config,
          onEdit: () => _editSyncConfig(config),
          onDelete: () => _deleteSyncConfig(config),
          onSync: () async {
            final success = await _performSync(config);
            if (success && mounted) {
              // 通知调用页面同步成功，需要刷新
              Navigator.of(context).pop(true);
            }
            return success;
          },
          onTest: () => _testSyncConfig(config),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.cloud_off,
            size: 64,
            color: isDark ? Theme.of(context).colorScheme.onSurfaceVariant : Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            '还没有配置同步服务',
            style: TextStyle(
              fontSize: 18,
              color: isDark ? Theme.of(context).colorScheme.onSurface : Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '点击右上角的 + 按钮添加同步配置',
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Theme.of(context).colorScheme.onSurfaceVariant : Colors.grey[500],
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _showAddSyncConfigDialog,
            icon: const Icon(Icons.add),
            label: const Text('添加同步配置'),
          ),
        ],
      ),
    );
  }

  void _showAddSyncConfigDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('选择同步方式'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.cloud),
              title: const Text('对象存储'),
              subtitle: const Text('支持AWS S3、阿里云OSS、腾讯云COS等'),
              onTap: () {
                Navigator.of(context).pop();
                _showObjectStorageConfigDialog();
              },
            ),
            ListTile(
              leading: const Icon(Icons.folder_shared),
              title: const Text('WebDAV'),
              subtitle: const Text('即将支持'),
              enabled: false,
              onTap: () {
                // TODO: 实现WebDAV配置
              },
            ),
            ListTile(
              leading: const Icon(Icons.folder_shared),
              title: const Text('FTP'),
              subtitle: const Text('即将支持'),
              enabled: false,
              onTap: () {
                // TODO: 实现FTP配置
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  void _showObjectStorageConfigDialog([SyncConfig? existingConfig]) {
    showDialog(
      context: context,
      builder: (context) => ObjectStorageConfigDialog(
        existingConfig: existingConfig,
        onSave: (config) async {
          await _syncService.addConfig(config);
          // 提供商会在addConfig时自动注册
          
          if (mounted) {
            setState(() {});
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('同步配置已保存')),
            );
          }
        },
      ),
    );
  }

  void _editSyncConfig(SyncConfig config) {
    if (config.providerType == SyncProviderType.objectStorage) {
      _showObjectStorageConfigDialog(config);
    }
  }

  void _deleteSyncConfig(SyncConfig config) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除同步配置'),
        content: Text('确定要删除同步配置 "${config.name}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await _syncService.removeConfig(config.id);
              if (mounted) {
                setState(() {});
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('同步配置已删除')),
                );
              }
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  Future<bool> _performSync(SyncConfig config) async {
    setState(() {
      _isLoading = true;
    });

    try {
      // 显示同步选项对话框
      final action = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('选择同步操作'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '词书同步',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                ListTile(
                  leading: const Icon(Icons.cloud_upload),
                  title: const Text('上传词书到云端'),
                  subtitle: const Text('将本地词书上传到云端\n⚠️ 需要本地有词书数据'),
                  onTap: () => Navigator.of(context).pop({
                    'type': 'wordbooks',
                    'action': 'upload',
                  }),
                ),
                ListTile(
                  leading: const Icon(Icons.cloud_download),
                  title: const Text('从云端下载词书'),
                  subtitle: const Text('从云端下载词书到本地\n⚠️ 会覆盖同名本地词书'),
                  onTap: () => Navigator.of(context).pop({
                    'type': 'wordbooks',
                    'action': 'download',
                  }),
                ),
                const Divider(),
                const Text(
                  '历史记录同步',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                ListTile(
                  leading: const Icon(Icons.sync, color: Colors.green),
                  title: const Text('智能同步历史记录（实验性）'),
                  subtitle: const Text('合并本地与云端数据\n⚠️ 目前实验性质，可能会损坏本地记录'),
                  onTap: () => Navigator.of(context).pop({
                    'type': 'history',
                    'action': 'smart_sync',
                  }),
                ),

              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
          ],
        ),
      );

      if (action != null) {
        SyncResult result;
        
        if (action['type'] == 'wordbooks') {
          result = await _syncService.syncWordbooks(
            config.id,
            upload: action['action'] == 'upload',
          );
        } else if (action['type'] == 'history') {
          // 使用进度对话框显示同步进度
          result = await showSyncProgressDialog<SyncResult>(
            context: context,
            title: '智能同步历史记录',
            syncFunction: (onProgress) async {
              return await _syncService.smartSyncHistory(
                config.id,
                onImportComplete: () {
                  // 刷新历史记录列表
                  if (mounted) {
                    context.read<HistoryProvider>().loadHistory();
                  }
                },
                onProgress: onProgress,
              );
            },
          ) ?? SyncResult.failure('同步被取消');
        } else {
          result = SyncResult.failure('未知的同步类型');
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result.success ? '同步成功' : '同步失败: ${result.message}'),
              backgroundColor: result.success ? Colors.green : Colors.red,
            ),
          );
        }
        return result.success;
      }
      return false;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('同步失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _testSyncConfig(SyncConfig config) async {
    setState(() {
      _isLoading = true;
    });

    try {
      final result = await _syncService.testConfig(config.id);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.success ? '连接测试成功' : '连接测试失败: ${result.message}'),
            backgroundColor: result.success ? Colors.green : Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('连接测试失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
}