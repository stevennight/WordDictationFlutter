import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../shared/providers/theme_provider.dart';
import '../../../shared/providers/history_provider.dart';
import '../../../core/services/config_service.dart';
import '../../../core/services/local_config_service.dart';
import '../../../core/config/app_version.dart';
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
      applicationVersion: _packageInfo?.version ?? AppVersion.version,
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
  final Map<String, Map<String, int>> currentRanges;

  const _AccuracyColorDialog({
    required this.configService,
    required this.currentRanges,
  });

  @override
  State<_AccuracyColorDialog> createState() => _AccuracyColorDialogState();
}

class _AccuracyColorDialogState extends State<_AccuracyColorDialog> {
  late TextEditingController redMinController;
  late TextEditingController redMaxController;
  late TextEditingController yellowMinController;
  late TextEditingController yellowMaxController;
  late TextEditingController blueMinController;
  late TextEditingController blueMaxController;
  late TextEditingController greenMinController;
  late TextEditingController greenMaxController;

  bool _isUpdating = false; // 防止循环更新

  @override
  void initState() {
    super.initState();
    redMinController = TextEditingController(text: widget.currentRanges['red']!['min'].toString());
    redMaxController = TextEditingController(text: widget.currentRanges['red']!['max'].toString());
    yellowMinController = TextEditingController(text: widget.currentRanges['yellow']!['min'].toString());
    yellowMaxController = TextEditingController(text: widget.currentRanges['yellow']!['max'].toString());
    blueMinController = TextEditingController(text: widget.currentRanges['blue']!['min'].toString());
    blueMaxController = TextEditingController(text: widget.currentRanges['blue']!['max'].toString());
    greenMinController = TextEditingController(text: widget.currentRanges['green']!['min'].toString());
    greenMaxController = TextEditingController(text: widget.currentRanges['green']!['max'].toString());
    
    // 添加监听器
    _addListeners();
  }

  void _addListeners() {
    // 红色区间监听器
    redMaxController.addListener(() => _updateAdjacentRange('redMax'));
    
    // 黄色区间监听器
    yellowMinController.addListener(() => _updateAdjacentRange('yellowMin'));
    yellowMaxController.addListener(() => _updateAdjacentRange('yellowMax'));
    
    // 蓝色区间监听器
    blueMinController.addListener(() => _updateAdjacentRange('blueMin'));
    blueMaxController.addListener(() => _updateAdjacentRange('blueMax'));
    
    // 绿色区间监听器
    greenMinController.addListener(() => _updateAdjacentRange('greenMin'));
  }

  void _updateAdjacentRange(String changedField) {
    if (_isUpdating) return;
    _isUpdating = true;
    
    try {
      switch (changedField) {
        case 'redMax':
          final redMax = int.tryParse(redMaxController.text);
          if (redMax != null && redMax >= 0 && redMax <= 100) {
            final newYellowMin = redMax + 1;
            if (newYellowMin <= 100) {
              yellowMinController.text = newYellowMin.toString();
            }
          }
          break;
          
        case 'yellowMin':
          final yellowMin = int.tryParse(yellowMinController.text);
          if (yellowMin != null && yellowMin >= 0 && yellowMin <= 100) {
            final newRedMax = yellowMin - 1;
            if (newRedMax >= 0) {
              redMaxController.text = newRedMax.toString();
            }
          }
          break;
          
        case 'yellowMax':
          final yellowMax = int.tryParse(yellowMaxController.text);
          if (yellowMax != null && yellowMax >= 0 && yellowMax <= 100) {
            final newBlueMin = yellowMax + 1;
            if (newBlueMin <= 100) {
              blueMinController.text = newBlueMin.toString();
            }
          }
          break;
          
        case 'blueMin':
          final blueMin = int.tryParse(blueMinController.text);
          if (blueMin != null && blueMin >= 0 && blueMin <= 100) {
            final newYellowMax = blueMin - 1;
            if (newYellowMax >= 0) {
              yellowMaxController.text = newYellowMax.toString();
            }
          }
          break;
          
        case 'blueMax':
          final blueMax = int.tryParse(blueMaxController.text);
          if (blueMax != null && blueMax >= 0 && blueMax <= 100) {
            final newGreenMin = blueMax + 1;
            if (newGreenMin <= 100) {
              greenMinController.text = newGreenMin.toString();
            }
          }
          break;
          
        case 'greenMin':
          final greenMin = int.tryParse(greenMinController.text);
          if (greenMin != null && greenMin >= 0 && greenMin <= 100) {
            final newBlueMax = greenMin - 1;
            if (newBlueMax >= 0) {
              blueMaxController.text = newBlueMax.toString();
            }
          }
          break;
      }
    } catch (e) {
      // 忽略解析错误
    }
    
    _isUpdating = false;
  }

  bool _validateRanges() {
    try {
      final redMin = int.parse(redMinController.text);
      final redMax = int.parse(redMaxController.text);
      final yellowMin = int.parse(yellowMinController.text);
      final yellowMax = int.parse(yellowMaxController.text);
      final blueMin = int.parse(blueMinController.text);
      final blueMax = int.parse(blueMaxController.text);
      final greenMin = int.parse(greenMinController.text);
      final greenMax = int.parse(greenMaxController.text);
      
      // 检查每个区间内部是否合理
      if (redMin < 0 || redMax > 100 || redMin > redMax ||
          yellowMin < 0 || yellowMax > 100 || yellowMin > yellowMax ||
          blueMin < 0 || blueMax > 100 || blueMin > blueMax ||
          greenMin < 0 || greenMax > 100 || greenMin > greenMax) {
        return false;
      }
      
      // 检查区间是否连续且不重叠
      final ranges = [redMin, redMax, yellowMin, yellowMax, blueMin, blueMax, greenMin, greenMax];
      ranges.sort();
      
      // 检查是否覆盖0-100且不重叠
      if (redMin != 0 || greenMax != 100) {
        return false;
      }
      
      if (redMax + 1 != yellowMin || yellowMax + 1 != blueMin || blueMax + 1 != greenMin) {
        return false;
      }
      
      return true;
    } catch (e) {
      return false;
    }
  }

  @override
  void dispose() {
    redMinController.dispose();
    redMaxController.dispose();
    yellowMinController.dispose();
    yellowMaxController.dispose();
    blueMinController.dispose();
    blueMaxController.dispose();
    greenMinController.dispose();
    greenMaxController.dispose();
    super.dispose();
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
            // 红色区间
            Row(
              children: [
                Container(
                  width: 20,
                  height: 20,
                  color: Colors.red,
                ),
                const SizedBox(width: 8),
                const Text('红色: '),
                Expanded(
                  child: TextField(
                    controller: redMinController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                      hintText: '最小值',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Text(' - '),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: redMaxController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                      hintText: '最大值',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // 黄色区间
            Row(
              children: [
                Container(
                  width: 20,
                  height: 20,
                  color: Colors.yellow[700],
                ),
                const SizedBox(width: 8),
                const Text('黄色: '),
                Expanded(
                  child: TextField(
                    controller: yellowMinController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                      hintText: '最小值',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Text(' - '),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: yellowMaxController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                      hintText: '最大值',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // 蓝色区间
            Row(
              children: [
                Container(
                  width: 20,
                  height: 20,
                  color: Colors.blue,
                ),
                const SizedBox(width: 8),
                const Text('蓝色: '),
                Expanded(
                  child: TextField(
                    controller: blueMinController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                      hintText: '最小值',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Text(' - '),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: blueMaxController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                      hintText: '最大值',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // 绿色区间
            Row(
              children: [
                Container(
                  width: 20,
                  height: 20,
                  color: Colors.green,
                ),
                const SizedBox(width: 8),
                const Text('绿色: '),
                Expanded(
                  child: TextField(
                    controller: greenMinController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                      hintText: '最小值',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Text(' - '),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: greenMaxController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                      hintText: '最大值',
                    ),
                  ),
                ),
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
            if (!_validateRanges()) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('区间设置不合理：请确保区间连续覆盖0-100且不重叠'),
                  duration: Duration(seconds: 3),
                ),
              );
              return;
            }
            
            try {
              final redMin = int.parse(redMinController.text);
              final redMax = int.parse(redMaxController.text);
              final yellowMin = int.parse(yellowMinController.text);
              final yellowMax = int.parse(yellowMaxController.text);
              final blueMin = int.parse(blueMinController.text);
              final blueMax = int.parse(blueMaxController.text);
              final greenMin = int.parse(greenMinController.text);
              final greenMax = int.parse(greenMaxController.text);
              
              final newRanges = {
                'red': {'min': redMin, 'max': redMax},
                'yellow': {'min': yellowMin, 'max': yellowMax},
                'blue': {'min': blueMin, 'max': blueMax},
                'green': {'min': greenMin, 'max': greenMax},
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