import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';

import 'core/database/database_helper.dart';
import 'core/services/config_service.dart';
import 'core/services/history_sync_service.dart';
import 'core/services/auto_sync_manager.dart';
import 'shared/providers/app_state_provider.dart';
import 'shared/providers/dictation_provider.dart';
import 'shared/providers/history_provider.dart';
import 'shared/providers/theme_provider.dart';
import 'features/home/screens/home_screen.dart';
import 'features/dictation/screens/dictation_screen.dart';
import 'features/history/screens/history_screen.dart';
import 'features/settings/screens/settings_screen.dart';

// 全局导航键，用于在服务中显示对话框
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize database factory for different platforms
  if (kIsWeb) {
    // For web platform
    databaseFactory = databaseFactoryFfiWeb;
  } else if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    // For desktop platforms
    databaseFactory = databaseFactoryFfi;
  }
  
  // Initialize database
  await DatabaseHelper.instance.database;
  
  // Initialize config service
  await ConfigService.getInstance();
  
  // Initialize history sync service (this will create device_id.txt)
  final historySyncService = HistorySyncService();
  await historySyncService.initialize();
  
  // Clear inProgress sessions on app startup
  final historyProvider = HistoryProvider();
  await historyProvider.clearInProgressSessions();
  
  // Initialize auto sync manager
  final autoSyncManager = AutoSyncManager();
  await autoSyncManager.initialize();
  
  // Set preferred orientations
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  
  runApp(const WordDictationApp());
}



class WordDictationApp extends StatefulWidget {
  const WordDictationApp({super.key});

  @override
  State<WordDictationApp> createState() => _WordDictationAppState();
}

class _WordDictationAppState extends State<WordDictationApp> {
  late ThemeProvider _themeProvider;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializeTheme();
  }

  Future<void> _initializeTheme() async {
    _themeProvider = ThemeProvider();
    await _themeProvider.initialize();
    if (mounted) {
      setState(() {
        _isInitialized = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return MaterialApp(
        title: '默写小助手',
        debugShowCheckedModeBanner: false,
        home: const Scaffold(
          body: Center(
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }

    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _themeProvider),
        ChangeNotifierProvider(create: (_) => AppStateProvider()),
        ChangeNotifierProvider(create: (_) => DictationProvider()),
        ChangeNotifierProvider(create: (_) => HistoryProvider()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return MaterialApp(
            title: '默写小助手',
            debugShowCheckedModeBanner: false,
            navigatorKey: navigatorKey,
            theme: themeProvider.lightTheme,
            darkTheme: themeProvider.darkTheme,
            themeMode: themeProvider.themeMode,
            home: const MainScreen(),
          );
        },
      ),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  
  final List<Widget> _screens = [
    const HomeScreen(),
    const HistoryScreen(),
    const SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Consumer<AppStateProvider>(
      builder: (context, appState, child) {
        // If in dictation mode, show dictation screen
        if (appState.isDictationMode) {
          return const DictationScreen();
        }
        
        // Otherwise show main navigation
        return Scaffold(
          body: IndexedStack(
            index: _currentIndex,
            children: _screens,
          ),
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
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
}