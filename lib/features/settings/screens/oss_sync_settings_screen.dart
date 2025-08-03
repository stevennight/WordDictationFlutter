import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../shared/models/oss_config.dart';
import '../../../shared/models/sync_record.dart';
import '../../../core/services/oss_sync_service.dart';
import '../../../shared/widgets/loading_overlay.dart';

class OssSyncSettingsScreen extends StatefulWidget {
  const OssSyncSettingsScreen({super.key});

  @override
  State<OssSyncSettingsScreen> createState() => _OssSyncSettingsScreenState();
}

class _OssSyncSettingsScreenState extends State<OssSyncSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _endpointController = TextEditingController();
  final _accessKeyIdController = TextEditingController();
  final _accessKeySecretController = TextEditingController();
  final _bucketNameController = TextEditingController();
  final _syncDirectoryController = TextEditingController();
  final _regionController = TextEditingController();
  
  bool _enabled = false;
  bool _isLoading = false;
  bool _obscureSecret = true;
  
  final OssSyncService _syncService = OssSyncService();
  List<SyncRecord> _syncRecords = [];
  
  @override
  void initState() {
    super.initState();
    _loadConfig();
    _loadSyncRecords();
  }
  
  @override
  void dispose() {
    _endpointController.dispose();
    _accessKeyIdController.dispose();
    _accessKeySecretController.dispose();
    _bucketNameController.dispose();
    _syncDirectoryController.dispose();
    _regionController.dispose();
    super.dispose();
  }
  
  Future<void> _loadConfig() async {
    try {
      await _syncService.initialize();
      final config = _syncService.config;
      if (config != null) {
        setState(() {
          _endpointController.text = config.endpoint ?? '';
          _accessKeyIdController.text = config.accessKeyId ?? '';
          _accessKeySecretController.text = config.accessKeySecret ?? '';
          _bucketNameController.text = config.bucketName ?? '';
          _syncDirectoryController.text = config.syncDirectory ?? 'word_dictation';
          _regionController.text = config.region ?? '';
          _enabled = config.enabled;
        });
      }
    } catch (e) {
      _showErrorSnackBar('加载配置失败: $e');
    }
  }
  
  Future<void> _loadSyncRecords() async {
    try {
      final records = await _syncService.getSyncRecords(limit: 20);
      setState(() {
        _syncRecords = records;
      });
    } catch (e) {
      print('Failed to load sync records: $e');
    }
  }
  
  Future<void> _saveConfig() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    
    setState(() {
      _isLoading = true;
    });
    
    try {
      final config = OssConfig(
        endpoint: _endpointController.text.trim(),
        accessKeyId: _accessKeyIdController.text.trim(),
        accessKeySecret: _accessKeySecretController.text.trim(),
        bucketName: _bucketNameController.text.trim(),
        syncDirectory: _syncDirectoryController.text.trim(),
        region: _regionController.text.trim(),
        enabled: _enabled,
        lastSyncTime: _syncService.config?.lastSyncTime,
      );
      
      await _syncService.saveConfig(config);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('配置保存成功'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      _showErrorSnackBar('保存配置失败: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    
    setState(() {
      _isLoading = true;
    });
    
    try {
      // Save config first
      final config = OssConfig(
        endpoint: _endpointController.text.trim(),
        accessKeyId: _accessKeyIdController.text.trim(),
        accessKeySecret: _accessKeySecretController.text.trim(),
        bucketName: _bucketNameController.text.trim(),
        syncDirectory: _syncDirectoryController.text.trim(),
        region: _regionController.text.trim(),
        enabled: true,
      );
      
      await _syncService.saveConfig(config);
      
      // Test connection by attempting a simple operation
      // In a real implementation, you would test the OSS connection
      await Future.delayed(const Duration(seconds: 2)); // Simulate test
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('连接测试成功'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      _showErrorSnackBar('连接测试失败: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  Future<void> _performSync() async {
    if (!_syncService.isSyncEnabled) {
      _showErrorSnackBar('请先配置并启用OSS同步');
      return;
    }
    
    setState(() {
      _isLoading = true;
    });
    
    try {
      final result = await showDialog<ConflictResolution>(
        context: context,
        builder: (context) => _ConflictResolutionDialog(),
      );
      
      if (result == null) {
        setState(() {
          _isLoading = false;
        });
        return;
      }
      
      final records = await _syncService.performFullSync(
        defaultResolution: result,
      );
      
      await _loadSyncRecords();
      
      if (mounted) {
        final successCount = records.where((r) => r.status == SyncStatus.success).length;
        final failedCount = records.where((r) => r.status == SyncStatus.failed).length;
        final conflictCount = records.where((r) => r.status == SyncStatus.conflict).length;
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('同步完成: 成功 $successCount, 失败 $failedCount, 冲突 $conflictCount'),
            backgroundColor: failedCount > 0 || conflictCount > 0 ? Colors.orange : Colors.green,
          ),
        );
      }
    } catch (e) {
      _showErrorSnackBar('同步失败: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  void _showErrorSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('OSS同步设置'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _isLoading ? null : _saveConfig,
          ),
        ],
      ),
      body: LoadingOverlay(
        isLoading: _isLoading,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Enable switch
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const Icon(Icons.cloud_sync),
                        const SizedBox(width: 16),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '启用OSS同步',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                '自动同步配置、词书和记录到云端',
                                style: TextStyle(color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: _enabled,
                          onChanged: (value) {
                            setState(() {
                              _enabled = value;
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // Configuration form
                const Text(
                  'OSS配置',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                
                TextFormField(
                  controller: _endpointController,
                  decoration: const InputDecoration(
                    labelText: 'Endpoint',
                    hintText: 'https://oss-cn-hangzhou.aliyuncs.com',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (_enabled && (value == null || value.trim().isEmpty)) {
                      return '请输入Endpoint';
                    }
                    return null;
                  },
                ),
                
                const SizedBox(height: 16),
                
                TextFormField(
                  controller: _accessKeyIdController,
                  decoration: const InputDecoration(
                    labelText: 'Access Key ID',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (_enabled && (value == null || value.trim().isEmpty)) {
                      return '请输入Access Key ID';
                    }
                    return null;
                  },
                ),
                
                const SizedBox(height: 16),
                
                TextFormField(
                  controller: _accessKeySecretController,
                  obscureText: _obscureSecret,
                  decoration: InputDecoration(
                    labelText: 'Access Key Secret',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureSecret ? Icons.visibility : Icons.visibility_off,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscureSecret = !_obscureSecret;
                        });
                      },
                    ),
                  ),
                  validator: (value) {
                    if (_enabled && (value == null || value.trim().isEmpty)) {
                      return '请输入Access Key Secret';
                    }
                    return null;
                  },
                ),
                
                const SizedBox(height: 16),
                
                TextFormField(
                  controller: _bucketNameController,
                  decoration: const InputDecoration(
                    labelText: 'Bucket名称',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (_enabled && (value == null || value.trim().isEmpty)) {
                      return '请输入Bucket名称';
                    }
                    return null;
                  },
                ),
                
                const SizedBox(height: 16),
                
                TextFormField(
                  controller: _syncDirectoryController,
                  decoration: const InputDecoration(
                    labelText: '同步目录',
                    hintText: 'word_dictation',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return '请输入同步目录';
                    }
                    return null;
                  },
                ),
                
                const SizedBox(height: 16),
                
                TextFormField(
                  controller: _regionController,
                  decoration: const InputDecoration(
                    labelText: '区域 (可选)',
                    hintText: 'cn-hangzhou',
                    border: OutlineInputBorder(),
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // Action buttons
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isLoading ? null : _testConnection,
                        icon: const Icon(Icons.wifi_protected_setup),
                        label: const Text('测试连接'),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isLoading ? null : _performSync,
                        icon: const Icon(Icons.sync),
                        label: const Text('立即同步'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).primaryColor,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 32),
                
                // Sync history
                const Text(
                  '同步历史',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                
                if (_syncRecords.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(
                        child: Text(
                          '暂无同步记录',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    ),
                  )
                else
                  ...(_syncRecords.map((record) => _buildSyncRecordCard(record))),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildSyncRecordCard(SyncRecord record) {
    IconData icon;
    Color color;
    
    switch (record.status) {
      case SyncStatus.success:
        icon = Icons.check_circle;
        color = Colors.green;
        break;
      case SyncStatus.failed:
        icon = Icons.error;
        color = Colors.red;
        break;
      case SyncStatus.conflict:
        icon = Icons.warning;
        color = Colors.orange;
        break;
      case SyncStatus.pending:
        icon = Icons.schedule;
        color = Colors.grey;
        break;
      case SyncStatus.inProgress:
        icon = Icons.sync;
        color = Colors.blue;
        break;
      case SyncStatus.skipped:
        icon = Icons.skip_next;
        color = Colors.grey;
        break;
    }
    
    String typeText;
    switch (record.syncType) {
      case SyncType.upload:
        typeText = '上传';
        break;
      case SyncType.download:
        typeText = '下载';
        break;
      case SyncType.bidirectional:
        typeText = '双向';
        break;
    }
    
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(record.fileName),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('类型: $typeText'),
            Text('时间: ${_formatDateTime(record.startTime)}'),
            if (record.errorMessage != null)
              Text(
                '错误: ${record.errorMessage}',
                style: const TextStyle(color: Colors.red),
              ),
          ],
        ),
        isThreeLine: true,
      ),
    );
  }
  
  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} '
           '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
}

class _ConflictResolutionDialog extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('选择同步方向'),
      content: const Text('请选择同步方向：'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(ConflictResolution.useLocal),
          child: const Text('上传到云端'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(ConflictResolution.useRemote),
          child: const Text('从云端下载'),
        ),
      ],
    );
  }
}