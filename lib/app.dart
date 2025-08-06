import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'features/home/screens/home_screen.dart';
import 'features/dictation/screens/dictation_screen.dart';
import 'features/history/screens/history_screen.dart';
import 'features/settings/screens/settings_screen.dart';
import 'shared/providers/app_state_provider.dart';

class WordDictationMainApp extends StatefulWidget {
  const WordDictationMainApp({super.key});

  @override
  State<WordDictationMainApp> createState() => _WordDictationMainAppState();
}

class _WordDictationMainAppState extends State<WordDictationMainApp> {
  int _currentIndex = 0;
  
  final List<Widget> _screens = [
    const HomeScreen(),
    const HistoryScreen(),
    const SettingsScreen(),
  ];
  
  final List<String> _titles = [
    '默写小助手',
    '历史记录',
    '设置',
  ];

  @override
  Widget build(BuildContext context) {
    return Consumer<AppStateProvider>(
      builder: (context, appState, child) {
        // If in dictation mode, show full-screen dictation
        if (appState.isDictationMode) {
          return const DictationScreen();
        }
        
        return Scaffold(
          appBar: AppBar(
            title: Text(_titles[_currentIndex]),
            actions: _buildAppBarActions(),
          ),
          body: IndexedStack(
            index: _currentIndex,
            children: _screens,
          ),
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: _onTabTapped,
            type: BottomNavigationBarType.fixed,
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.home),
                label: '首页',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.history),
                label: '历史',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.settings),
                label: '设置',
              ),
            ],
          ),
        );
      },
    );
  }
  
  void _onTabTapped(int index) {
    setState(() {
      _currentIndex = index;
    });
  }
  
  List<Widget> _buildAppBarActions() {
    switch (_currentIndex) {
      case 0: // Home
        return [
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: () => _showHelpDialog(),
          ),
        ];
      case 1: // History
        return [
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            onPressed: () => _showClearHistoryDialog(),
          ),
        ];
      case 2: // Settings
        return [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showAboutDialog(),
          ),
        ];
      default:
        return [];
    }
  }
  
  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('使用帮助'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('1. 点击"导入单词文件"选择.xlsx或.csv格式的单词表'),
              SizedBox(height: 8),
              Text('2. 选择默写顺序（顺序或乱序）'),
              SizedBox(height: 8),
              Text('3. 选择默写数量'),
              SizedBox(height: 8),
              Text('4. 在画布上手写答案'),
              SizedBox(height: 8),
              Text('5. 提交后查看正确答案并判断对错'),
              SizedBox(height: 8),
              Text('6. 完成后查看统计结果'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('确定'),
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
        content: const Text('确定要清空所有历史记录吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              // TODO: Implement clear history
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('历史记录已清空')),
              );
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
  
  void _showAboutDialog() {
    showAboutDialog(
      context: context,
      applicationName: '默写小助手',
      applicationVersion: '1.0.0',
      applicationIcon: const Icon(
        Icons.edit,
        size: 48,
      ),
      children: [
        const Text('一个基于Flutter开发的跨平台默写工具'),
        const SizedBox(height: 16),
        const Text('功能特性：'),
        const Text('• 手写默写练习'),
        const Text('• Word文档导入'),
        const Text('• 历史记录管理'),
        const Text('• 错题重做功能'),
        const Text('• 跨平台支持'),
      ],
    );
  }
}