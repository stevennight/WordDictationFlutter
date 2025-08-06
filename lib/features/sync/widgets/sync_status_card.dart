import 'package:flutter/material.dart';
import '../../../core/services/sync_service.dart';

class SyncStatusCard extends StatelessWidget {
  final SyncConfig config;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final Future<bool> Function() onSync;
  final VoidCallback onTest;

  const SyncStatusCard({
    super.key,
    required this.config,
    required this.onEdit,
    required this.onDelete,
    required this.onSync,
    required this.onTest,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _buildProviderIcon(),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        config.name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _getProviderDisplayName(),
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                _buildStatusChip(context),
              ],
            ),
            const SizedBox(height: 16),
            _buildConfigInfo(),
            const SizedBox(height: 16),
            _buildLastSyncInfo(context),
            const SizedBox(height: 16),
            _buildActionButtons(context),
          ],
        ),
      ),
    );
  }

  Widget _buildProviderIcon() {
    IconData iconData;
    Color iconColor;
    
    switch (config.providerType) {
      case SyncProviderType.objectStorage:
        iconData = Icons.cloud;
        iconColor = Colors.blue;
        break;
      case SyncProviderType.webdav:
        iconData = Icons.folder_shared;
        iconColor = Colors.orange;
        break;
      case SyncProviderType.ftp:
        iconData = Icons.folder_shared;
        iconColor = Colors.green;
        break;
    }
    
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: iconColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        iconData,
        color: iconColor,
        size: 24,
      ),
    );
  }

  Widget _buildStatusChip(BuildContext context) {
    final isEnabled = config.enabled;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Chip(
      label: Text(
        isEnabled ? '已启用' : '已禁用',
        style: TextStyle(
          color: isEnabled 
              ? (isDark ? Colors.green[300] : Colors.green[700])
              : (isDark ? Theme.of(context).colorScheme.onSurfaceVariant : Colors.grey[600]),
          fontSize: 12,
        ),
      ),
      backgroundColor: isEnabled 
          ? (isDark ? Colors.green[900]!.withOpacity(0.3) : Colors.green[50])
          : (isDark ? Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3) : Colors.grey[100]),
      side: BorderSide(
        color: isEnabled 
            ? (isDark ? Colors.green[700]!.withOpacity(0.5) : Colors.green[200]!)
            : (isDark ? Theme.of(context).colorScheme.outline.withOpacity(0.3) : Colors.grey[300]!),
      ),
     );
  }

  Widget _buildConfigInfo() {
    final settings = config.settings;
    List<Widget> infoItems = [];
    
    if (config.providerType == SyncProviderType.objectStorage) {
      infoItems = [
        _buildInfoItem('存储桶', settings['bucket'] ?? 'N/A'),
        _buildInfoItem('区域', settings['region'] ?? 'N/A'),
        _buildInfoItem('端点', settings['endpoint'] ?? 'N/A'),
      ];
    }
    
    return Column(
      children: infoItems,
    );
  }

  Widget _buildInfoItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ),
          const Text(': '),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 12,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLastSyncInfo(BuildContext context) {
    final lastSyncTime = config.lastSyncTime;
    final autoSync = config.autoSync;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3) : Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isDark ? Theme.of(context).colorScheme.outline.withOpacity(0.3) : Colors.grey[200]!),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                Icons.schedule,
                size: 16,
                color: isDark ? Theme.of(context).colorScheme.onSurfaceVariant : Colors.grey[600],
              ),
              const SizedBox(width: 8),
              Text(
                '上次同步: ${lastSyncTime != null ? _formatDateTime(lastSyncTime) : '从未同步'}',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Theme.of(context).colorScheme.onSurfaceVariant : Colors.grey[600],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                autoSync ? Icons.sync : Icons.sync_disabled,
                size: 16,
                color: isDark ? Theme.of(context).colorScheme.onSurfaceVariant : Colors.grey[600],
              ),
              const SizedBox(width: 8),
              Text(
                autoSync ? '自动同步: 每${_formatDuration(config.syncInterval)}' : '手动同步',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Theme.of(context).colorScheme.onSurfaceVariant : Colors.grey[600],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onTest,
            icon: const Icon(Icons.wifi_protected_setup, size: 16),
            label: const Text('测试连接'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 8),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: config.enabled ? () async {
              await onSync();
            } : null,
            icon: const Icon(Icons.sync, size: 16),
            label: const Text('同步'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 8),
            ),
          ),
        ),
        const SizedBox(width: 8),
        PopupMenuButton<String>(
          onSelected: (value) {
            switch (value) {
              case 'edit':
                onEdit();
                break;
              case 'delete':
                onDelete();
                break;
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'edit',
              child: ListTile(
                leading: Icon(Icons.edit),
                title: Text('编辑'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: ListTile(
                leading: Icon(Icons.delete, color: Colors.red),
                title: Text('删除', style: TextStyle(color: Colors.red)),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(
              Icons.more_vert,
              size: 16,
              color: Colors.grey[600],
            ),
          ),
        ),
      ],
    );
  }

  String _getProviderDisplayName() {
    switch (config.providerType) {
      case SyncProviderType.objectStorage:
        return '对象存储';
      case SyncProviderType.webdav:
        return 'WebDAV';
      case SyncProviderType.ftp:
        return 'FTP';
    }
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    
    if (difference.inDays > 0) {
      return '${difference.inDays}天前';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}小时前';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}分钟前';
    } else {
      return '刚刚';
    }
  }

  String _formatDuration(Duration duration) {
    if (duration.inDays > 0) {
      return '${duration.inDays}天';
    } else if (duration.inHours > 0) {
      return '${duration.inHours}小时';
    } else {
      return '${duration.inMinutes}分钟';
    }
  }
}