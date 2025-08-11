import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../../core/services/sync_service.dart';
import '../../../core/services/object_storage_sync_provider.dart';

class ObjectStorageConfigDialog extends StatefulWidget {
  final SyncConfig? existingConfig;
  final Function(SyncConfig) onSave;

  const ObjectStorageConfigDialog({
    super.key,
    this.existingConfig,
    required this.onSave,
  });

  @override
  State<ObjectStorageConfigDialog> createState() => _ObjectStorageConfigDialogState();
}

class _ObjectStorageConfigDialogState extends State<ObjectStorageConfigDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _endpointController = TextEditingController();
  final _regionController = TextEditingController();
  final _bucketController = TextEditingController();
  final _accessKeyController = TextEditingController();
  final _secretKeyController = TextEditingController();
  final _pathPrefixController = TextEditingController();
  
  ObjectStorageType _selectedStorageType = ObjectStorageType.awsS3;
  UrlStyle _selectedUrlStyle = UrlStyle.pathStyle;
  bool _useSSL = true;
  bool _autoSync = false;
  Duration _syncInterval = const Duration(hours: 1);
  bool _obscureSecretKey = true;
  bool _isLoading = false;
  bool _enabled = true;

  @override
  void initState() {
    super.initState();
    _initializeFields();
  }

  void _initializeFields() {
    if (widget.existingConfig != null) {
      final config = widget.existingConfig!;
      final storageConfig = ObjectStorageConfig.fromMap(config.settings);
      
      _nameController.text = config.name;
      _selectedStorageType = storageConfig.storageType;
      _endpointController.text = storageConfig.endpoint;
      _regionController.text = storageConfig.region;
      _bucketController.text = storageConfig.bucket;
      _accessKeyController.text = storageConfig.accessKeyId;
      _secretKeyController.text = storageConfig.secretAccessKey;
      _pathPrefixController.text = storageConfig.pathPrefix;
      _selectedUrlStyle = storageConfig.urlStyle;
      _useSSL = storageConfig.useSSL;
      _autoSync = config.autoSync;
      _syncInterval = config.syncInterval;
      _enabled = config.enabled;
    } else {
      _pathPrefixController.text = 'wordDictationSync';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _endpointController.dispose();
    _regionController.dispose();
    _bucketController.dispose();
    _accessKeyController.dispose();
    _secretKeyController.dispose();
    _pathPrefixController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.8,
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            _buildHeader(),
            const SizedBox(height: 16),
            Expanded(
              child: _buildForm(),
            ),
            const SizedBox(height: 16),
            _buildActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const Icon(Icons.cloud, size: 24),
        const SizedBox(width: 12),
        Text(
          widget.existingConfig != null ? '编辑对象存储配置' : '添加对象存储配置',
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const Spacer(),
        IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close),
        ),
      ],
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildBasicSettings(),
            const SizedBox(height: 24),
            _buildConnectionSettings(),
            const SizedBox(height: 24),
            _buildSyncSettings(),
          ],
        ),
      ),
    );
  }

  Widget _buildBasicSettings() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '基本设置',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: '配置名称',
                hintText: '为这个同步配置起个名字',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return '请输入配置名称';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<ObjectStorageType>(
              value: _selectedStorageType,
              decoration: const InputDecoration(
                labelText: '存储类型',
                border: OutlineInputBorder(),
              ),
              items: ObjectStorageType.values.map((type) {
                return DropdownMenuItem(
                  value: type,
                  child: Text(_getStorageTypeDisplayName(type)),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _selectedStorageType = value;
                    _updateEndpointForStorageType(value);
                  });
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionSettings() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '连接设置',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _endpointController,
              decoration: const InputDecoration(
                labelText: '端点地址',
                hintText: 's3.amazonaws.com',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return '请输入端点地址';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<UrlStyle>(
              value: _selectedUrlStyle,
              decoration: const InputDecoration(
                labelText: 'URL 风格',
                border: OutlineInputBorder(),
                helperText: 'Path: endpoint/bucket/key\nHost: bucket.endpoint/key',
              ),
              items: UrlStyle.values.map((style) {
                return DropdownMenuItem(
                  value: style,
                  child: Text(_getUrlStyleDisplayName(style)),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _selectedUrlStyle = value;
                  });
                }
              },
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _regionController,
                    decoration: const InputDecoration(
                      labelText: '区域',
                      hintText: 'us-east-1',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return '请输入区域';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _bucketController,
                    decoration: const InputDecoration(
                      labelText: '存储桶名称',
                      hintText: 'my-wordbook-bucket',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return '请输入存储桶名称';
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _accessKeyController,
              decoration: const InputDecoration(
                labelText: 'Access Key ID',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return '请输入Access Key ID';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _secretKeyController,
              obscureText: _obscureSecretKey,
              decoration: InputDecoration(
                labelText: 'Secret Access Key',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureSecretKey ? Icons.visibility : Icons.visibility_off,
                  ),
                  onPressed: () {
                    setState(() {
                      _obscureSecretKey = !_obscureSecretKey;
                    });
                  },
                ),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return '请输入Secret Access Key';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _pathPrefixController,
              decoration: const InputDecoration(
                labelText: '存储路径前缀',
                hintText: 'wordDictationSync',
                border: OutlineInputBorder(),
                helperText: '在存储桶中的文件夹路径',
              ),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('使用SSL'),
              subtitle: const Text('推荐开启以确保数据传输安全'),
              value: _useSSL,
              onChanged: (value) {
                setState(() {
                  _useSSL = value;
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSyncSettings() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '同步设置',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('启用同步'),
              subtitle: const Text('启用或禁用此同步配置'),
              value: _enabled,
              onChanged: (value) {
                setState(() {
                  _enabled = value;
                });
              },
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              title: const Text('自动同步'),
              subtitle: const Text('在应用启动和定时间隔时自动同步历史记录数据'),
              value: _autoSync,
              onChanged: _enabled ? (value) {
                setState(() {
                  _autoSync = value;
                });
              } : null,
            ),
            if (_autoSync) ...[
              const SizedBox(height: 16),
              DropdownButtonFormField<Duration>(
                value: _syncInterval,
                decoration: const InputDecoration(
                  labelText: '同步间隔',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(
                    value: Duration(minutes: 5),
                    child: Text('5分钟'),
                  ),
                  const DropdownMenuItem(
                    value: Duration(minutes: 10),
                    child: Text('10分钟'),
                  ),
                  const DropdownMenuItem(
                    value: Duration(minutes: 15),
                    child: Text('15分钟'),
                  ),
                  const DropdownMenuItem(
                    value: Duration(minutes: 30),
                    child: Text('30分钟'),
                  ),
                  const DropdownMenuItem(
                    value: Duration(hours: 1),
                    child: Text('1小时'),
                  ),
                  const DropdownMenuItem(
                    value: Duration(hours: 6),
                    child: Text('6小时'),
                  ),
                  const DropdownMenuItem(
                    value: Duration(hours: 12),
                    child: Text('12小时'),
                  ),
                  const DropdownMenuItem(
                    value: Duration(days: 1),
                    child: Text('1天'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _syncInterval = value;
                    });
                  }
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActions() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: ElevatedButton(
            onPressed: _isLoading ? null : _saveConfig,
            child: _isLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(widget.existingConfig != null ? '保存' : '添加'),
          ),
        ),
      ],
    );
  }

  String _getStorageTypeDisplayName(ObjectStorageType type) {
    switch (type) {
      case ObjectStorageType.awsS3:
        return 'AWS S3';
      case ObjectStorageType.alibabaOSS:
        return '阿里云 OSS';
      case ObjectStorageType.tencentCOS:
        return '腾讯云 COS';
      case ObjectStorageType.minIO:
        return 'MinIO';
      case ObjectStorageType.custom:
        return '自定义 S3 兼容';
    }
  }

  String _getUrlStyleDisplayName(UrlStyle style) {
    switch (style) {
      case UrlStyle.pathStyle:
        return 'Path 风格 (推荐)';
      case UrlStyle.hostStyle:
        return 'Host 风格';
    }
  }

  void _updateEndpointForStorageType(ObjectStorageType type) {
    switch (type) {
      case ObjectStorageType.awsS3:
        _endpointController.text = 's3.amazonaws.com';
        break;
      case ObjectStorageType.alibabaOSS:
        _endpointController.text = 'oss-cn-hangzhou.aliyuncs.com';
        break;
      case ObjectStorageType.tencentCOS:
        _endpointController.text = 'cos.ap-beijing.myqcloud.com';
        break;
      case ObjectStorageType.minIO:
        _endpointController.text = 'localhost:9000';
        break;
      case ObjectStorageType.custom:
        _endpointController.clear();
        break;
    }
  }

  void _saveConfig() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final storageConfig = ObjectStorageConfig(
        storageType: _selectedStorageType,
        endpoint: _endpointController.text.trim(),
        region: _regionController.text.trim(),
        bucket: _bucketController.text.trim(),
        accessKeyId: _accessKeyController.text.trim(),
        secretAccessKey: _secretKeyController.text.trim(),
        useSSL: _useSSL,
        pathPrefix: _pathPrefixController.text.trim(),
        urlStyle: _selectedUrlStyle,
      );

      final syncConfig = SyncConfig(
        id: widget.existingConfig?.id ?? const Uuid().v4(),
        name: _nameController.text.trim(),
        providerType: SyncProviderType.objectStorage,
        settings: storageConfig.toMap(),
        autoSync: _autoSync,
        syncInterval: _syncInterval,
        lastSyncTime: widget.existingConfig?.lastSyncTime,
        enabled: _enabled,
      );

      widget.onSave(syncConfig);
      Navigator.of(context).pop();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('保存配置失败: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
}