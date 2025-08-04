import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../shared/providers/theme_provider.dart';
import '../../../shared/providers/history_provider.dart';
import '../../../core/services/config_service.dart';
import '../../../core/services/local_config_service.dart';
import '../widgets/settings_section.dart';
import '../widgets/settings_tile.dart';
import '../widgets/about_dialog.dart';
import '../../sync/sync_settings_screen.dart';


class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  PackageInfo? _packageInfo;
  ConfigService? _configService;

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
  }

  Future<void> _loadPackageInfo() async {
    final packageInfo = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _packageInfo = packageInfo;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            title: const Text('设置'),
            floating: true,
            snap: true,
            backgroundColor: Theme.of(context).colorScheme.surface,
            foregroundColor: Theme.of(context).colorScheme.onSurface,
            surfaceTintColor: Theme.of(context).colorScheme.primary,
          ),
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
            // Appearance section
            SettingsSection(
              title: '外观设置',
              icon: Icons.palette,
              children: [
                Consumer<ThemeProvider>(
                  builder: (context, themeProvider, child) {
                    return SettingsTile(
                      title: '主题模式',
                      subtitle: themeProvider.themeName,
                      leading: Icon(
                        themeProvider.isDarkMode
                            ? Icons.dark_mode
                            : Icons.light_mode,
                      ),
                      onTap: () {
                        themeProvider.toggleTheme();
                      },
                    );
                  },
                ),
                SettingsTile(
                  title: '准确率颜色设置',
                  subtitle: '自定义准确率颜色区间',
                  leading: const Icon(Icons.color_lens),
                  onTap: () => _showAccuracyColorDialog(),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Data management section
            SettingsSection(
              title: '数据管理',
              icon: Icons.storage,
              children: [
                SettingsTile(
                  title: '同步设置',
                  subtitle: '配置云端同步服务',
                  leading: const Icon(Icons.sync),
                  onTap: () => _navigateToSyncSettings(),
                ),
                SettingsTile(
                  title: '清空历史记录',
                  subtitle: '删除所有默写历史记录',
                  leading: const Icon(Icons.delete_sweep),
                  onTap: () => _showClearHistoryDialog(),
                ),
                SettingsTile(
                  title: '导出数据',
                  subtitle: '导出历史记录和设置',
                  leading: const Icon(Icons.download),
                  onTap: () => _exportData(),
                ),
                SettingsTile(
                  title: '导入数据',
                  subtitle: '从备份文件导入数据',
                  leading: const Icon(Icons.upload),
                  onTap: () => _importData(),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // General settings section
            SettingsSection(
              title: '通用设置',
              icon: Icons.settings,
              children: [
                SettingsTile(
                  title: '默认画笔大小',
                  subtitle: '设置手写画笔的默认粗细',
                  leading: const Icon(Icons.brush),
                  onTap: () => _showBrushSizeDialog(),
                ),
                SettingsTile(
                  title: '历史记录数量限制',
                  subtitle: '设置保存的历史记录最大数量',
                  leading: const Icon(Icons.history),
                  onTap: () => _showHistoryLimitDialog(),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Help and support section
            SettingsSection(
              title: '帮助与支持',
              icon: Icons.help,
              children: [
                SettingsTile(
                  title: '使用教程',
                  subtitle: '查看应用使用指南',
                  leading: const Icon(Icons.school),
                  onTap: () => _showTutorial(),
                ),
                SettingsTile(
                  title: '常见问题',
                  subtitle: '查看常见问题解答',
                  leading: const Icon(Icons.quiz),
                  onTap: () => _showFAQ(),
                ),
                SettingsTile(
                  title: '反馈建议',
                  subtitle: '向我们提供反馈和建议',
                  leading: const Icon(Icons.feedback),
                  onTap: () => _showFeedback(),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // About section
            SettingsSection(
              title: '关于',
              icon: Icons.info,
              children: [
                SettingsTile(
                  title: '应用版本',
                  subtitle: _packageInfo?.version ?? '加载中...',
                  leading: const Icon(Icons.info_outline),
                  onTap: () => _showAboutDialog(),
                ),
                SettingsTile(
                  title: '检查更新',
                  subtitle: '检查是否有新版本可用',
                  leading: const Icon(Icons.system_update),
                  onTap: () => _checkForUpdates(),
                ),
                SettingsTile(
                  title: '开源许可',
                  subtitle: '查看开源组件许可信息',
                  leading: const Icon(Icons.code),
                  onTap: () => _showLicenses(),
                ),
              ],
            ),
            
                const SizedBox(height: 32),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  void _showClearHistoryDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空历史记录'),
        content: const Text('确定要删除所有历史记录吗？此操作无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              try {
                await context.read<HistoryProvider>().clearAllHistory();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('历史记录已清空'),
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('清空失败: $e'),
                      backgroundColor: Theme.of(context).colorScheme.error,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _exportData() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('导出功能待实现'),
      ),
    );
  }

  void _importData() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('导入功能待实现'),
      ),
    );
  }

  void _showBrushSizeDialog() async {
    // Get current brush size from settings
    final configService = await ConfigService.getInstance();
    double currentSize = (await configService.getSetting('default_brush_size'))?.toDouble() ?? 3.0;
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('设置画笔大小'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('当前大小: ${currentSize.toInt()}'),
              const SizedBox(height: 16),
              Slider(
                value: currentSize,
                min: 1.0,
                max: 10.0,
                divisions: 9,
                onChanged: (value) {
                  setState(() {
                    currentSize = value;
                  });
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () async {
                try {
                  // Save brush size to settings
                  await configService.setSetting('default_brush_size', currentSize);
                  Navigator.of(context).pop();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('画笔大小已保存'),
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('保存失败: $e'),
                        backgroundColor: Theme.of(context).colorScheme.error,
                      ),
                    );
                  }
                }
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  void _showAutoSaveDialog() {
    int currentInterval = 30; // TODO: Get from settings
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('设置自动保存间隔'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<int>(
              title: const Text('15秒'),
              value: 15,
              groupValue: currentInterval,
              onChanged: (value) {
                Navigator.of(context).pop();
                // TODO: Save to settings
              },
            ),
            RadioListTile<int>(
              title: const Text('30秒'),
              value: 30,
              groupValue: currentInterval,
              onChanged: (value) {
                Navigator.of(context).pop();
                // TODO: Save to settings
              },
            ),
            RadioListTile<int>(
              title: const Text('60秒'),
              value: 60,
              groupValue: currentInterval,
              onChanged: (value) {
                Navigator.of(context).pop();
                // TODO: Save to settings
              },
            ),
            RadioListTile<int>(
              title: const Text('关闭自动保存'),
              value: 0,
              groupValue: currentInterval,
              onChanged: (value) {
                Navigator.of(context).pop();
                // TODO: Save to settings
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

  void _showTutorial() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('使用教程功能待实现'),
      ),
    );
  }

  void _showFAQ() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('常见问题功能待实现'),
      ),
    );
  }

  void _showFeedback() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('反馈功能待实现'),
      ),
    );
  }

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (context) => CustomAboutDialog(
        packageInfo: _packageInfo,
      ),
    );
  }

  void _checkForUpdates() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('检查更新功能待实现'),
      ),
    );
  }

  void _showLicenses() {
    showLicensePage(
      context: context,
      applicationName: _packageInfo?.appName ?? 'Word Dictation',
      applicationVersion: _packageInfo?.version ?? '1.0.0',
    );
  }

  void _navigateToSyncSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const SyncSettingsScreen(),
      ),
    );
  }

  void _showHistoryLimitDialog() async {
    _configService ??= await ConfigService.getInstance();
    final currentLimit = _configService!.getHistoryLimit();
    final controller = TextEditingController(text: currentLimit.toString());

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('历史记录数量限制'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('设置保存的历史记录最大数量，超出数量后将自动删除最旧的记录。'),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '数量限制',
                hintText: '请输入数字（默认50）',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              final input = controller.text.trim();
              final limit = int.tryParse(input);
              
              if (limit == null || limit < 1) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('请输入有效的数字（大于0）')),
                );
                return;
              }
              
              await _configService!.setHistoryLimit(limit);
              
              if (mounted) {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('历史记录数量限制已设置为 $limit 条')),
                );
                
                // 重新加载历史记录以应用新的限制
                final historyProvider = Provider.of<HistoryProvider>(context, listen: false);
                await historyProvider.loadHistory();
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _showAccuracyColorDialog() async {
    final configService = await LocalConfigService.getInstance();
    final currentRanges = await configService.getAccuracyColorRanges();
    
    showDialog(
      context: context,
      builder: (context) => _AccuracyColorDialog(
        configService: configService,
        currentRanges: currentRanges,
      ),
    );
  }
}

class _AccuracyColorDialog extends StatefulWidget {
  final LocalConfigService configService;
  final Map<String, int> currentRanges;

  const _AccuracyColorDialog({
    required this.configService,
    required this.currentRanges,
  });

  @override
  State<_AccuracyColorDialog> createState() => _AccuracyColorDialogState();
}

class _AccuracyColorDialogState extends State<_AccuracyColorDialog> {
  late TextEditingController redMaxController;
  late TextEditingController yellowMaxController;
  late TextEditingController blueMaxController;

  @override
  void initState() {
    super.initState();
    redMaxController = TextEditingController(text: widget.currentRanges['red_max'].toString());
    yellowMaxController = TextEditingController(text: widget.currentRanges['yellow_max'].toString());
    blueMaxController = TextEditingController(text: widget.currentRanges['blue_max'].toString());
    
    // 添加监听器以实现自动更新
    redMaxController.addListener(_updateUI);
    yellowMaxController.addListener(_updateUI);
    blueMaxController.addListener(_updateUI);
  }

  @override
  void dispose() {
    redMaxController.dispose();
    yellowMaxController.dispose();
    blueMaxController.dispose();
    super.dispose();
  }

  void _updateUI() {
    setState(() {});
  }

  int _getYellowStart() {
    try {
      return int.parse(redMaxController.text) + 1;
    } catch (e) {
      return 0;
    }
  }

  int _getBlueStart() {
    try {
      return int.parse(yellowMaxController.text) + 1;
    } catch (e) {
      return 0;
    }
  }

  int _getGreenStart() {
    try {
      return int.parse(blueMaxController.text) + 1;
    } catch (e) {
      return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('准确率颜色设置'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('设置不同准确率区间对应的颜色：'),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  width: 20,
                  height: 20,
                  color: Colors.red,
                ),
                const SizedBox(width: 8),
                const Text('红色: 0 - '),
                Expanded(
                  child: TextField(
                    controller: redMaxController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Container(
                  width: 20,
                  height: 20,
                  color: Colors.yellow[700],
                ),
                const SizedBox(width: 8),
                Text('黄色: ${_getYellowStart()} - '),
                Expanded(
                  child: TextField(
                    controller: yellowMaxController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Container(
                  width: 20,
                  height: 20,
                  color: Colors.blue,
                ),
                const SizedBox(width: 8),
                Text('蓝色: ${_getBlueStart()} - '),
                Expanded(
                  child: TextField(
                    controller: blueMaxController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Container(
                  width: 20,
                  height: 20,
                  color: Colors.green,
                ),
                const SizedBox(width: 8),
                Text('绿色: ${_getGreenStart()} - 100'),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              '注意：请确保区间完整覆盖0-100，且不重叠',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () async {
            try {
              final redMax = int.parse(redMaxController.text);
              final yellowMax = int.parse(yellowMaxController.text);
              final blueMax = int.parse(blueMaxController.text);
              final greenMin = _getGreenStart(); // 自动计算绿色区间开始值
              
              // 验证区间是否合理
              if (redMax < 0 || redMax >= 100 ||
                  yellowMax <= redMax || yellowMax >= 100 ||
                  blueMax <= yellowMax || blueMax >= 100 ||
                  greenMin <= blueMax || greenMin > 100) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('区间设置不合理，请检查数值')),
                );
                return;
              }
              
              final newRanges = {
                'red_max': redMax,
                'yellow_max': yellowMax,
                'blue_max': blueMax,
                'green_min': greenMin,
              };
              
              await widget.configService.setAccuracyColorRanges(newRanges);
              
              if (mounted) {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('准确率颜色设置已保存')),
                );
              }
            } catch (e) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('请输入有效的数字')),
              );
            }
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}