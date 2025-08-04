import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

class CustomAboutDialog extends StatelessWidget {
  final PackageInfo? packageInfo;

  const CustomAboutDialog({
    super.key,
    this.packageInfo,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('关于应用'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // App icon and name
            Center(
              child: Column(
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      Icons.edit_note,
                      size: 48,
                      color: Theme.of(context).colorScheme.onPrimary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    packageInfo?.appName ?? 'Word Dictation',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '版本 ${packageInfo?.version ?? '1.0.0'}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            
            // App description
            Text(
              '应用简介',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Word Dictation 是一款专为英语学习者设计的单词默写应用。支持从Excel、CSV和JSON文件导入单词，提供手写练习功能，并能记录学习历史和统计数据。',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            
            const SizedBox(height: 16),
            
            // Features
            Text(
              '主要功能',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            _buildFeatureItem(
              context,
              Icons.file_upload,
              '导入Excel、CSV或JSON格式的单词列表',
            ),
            _buildFeatureItem(
              context,
              Icons.edit,
              '手写练习，支持多种画笔工具',
            ),
            _buildFeatureItem(
              context,
              Icons.shuffle,
              '顺序或随机默写模式',
            ),
            _buildFeatureItem(
              context,
              Icons.history,
              '详细的学习历史和统计分析',
            ),
            _buildFeatureItem(
              context,
              Icons.refresh,
              '错题重做功能',
            ),
            _buildFeatureItem(
              context,
              Icons.palette,
              '多主题支持',
            ),
            
            const SizedBox(height: 16),
            
            // Build info
            Text(
              '构建信息',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            _buildInfoRow('包名', packageInfo?.packageName ?? 'com.example.word_dictation'),
            _buildInfoRow('构建号', packageInfo?.buildNumber ?? '1'),
            _buildInfoRow('构建签名', packageInfo?.buildSignature ?? 'Debug'),
            
            const SizedBox(height: 16),
            
            // Copyright
            Center(
              child: Column(
                children: [
                  Text(
                    '© 2024 Word Dictation',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '使用 Flutter 构建',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.of(context).pop();
            showLicensePage(
              context: context,
              applicationName: packageInfo?.appName ?? 'Word Dictation',
              applicationVersion: packageInfo?.version ?? '1.0.0',
            );
          },
          child: const Text('开源许可'),
        ),
      ],
    );
  }

  Widget _buildFeatureItem(BuildContext context, IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
          ),
          const Text(
            ': ',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
          ),
        ],
      ),
    );
  }
}