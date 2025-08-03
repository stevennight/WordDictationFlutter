import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';

import 'core/database/database_helper.dart';
import 'core/services/config_service.dart';
import 'core/services/oss_sync_service.dart';
import 'shared/providers/app_state_provider.dart';
import 'shared/providers/dictation_provider.dart';
import 'shared/providers/history_provider.dart';
import 'shared/providers/theme_provider.dart';
import 'shared/models/sync_record.dart';
import 'features/home/screens/home_screen.dart';
import 'features/dictation/screens/dictation_screen.dart';
import 'features/history/screens/history_screen.dart';
import 'features/settings/screens/settings_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize database factory for desktop platforms
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    databaseFactory = databaseFactoryFfi;
  }
  
  // Initialize database
  await DatabaseHelper.instance.database;
  
  // Initialize config service
  await ConfigService.getInstance();
  
  // Initialize OSS sync service
  final ossSyncService = OssSyncService();
  await ossSyncService.initialize();
  
  // Clear inProgress sessions on app startup
  final historyProvider = HistoryProvider();
  await historyProvider.clearInProgressSessions();
  
  // Note: Startup sync will be handled in MainScreen after UI is ready
  
  // Set preferred orientations
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  
  runApp(const WordDictationApp());
}

/// Perform sync with retry mechanism and user choice
Future<void> _performSyncWithRetry(
  OssSyncService syncService,
  String context,
  ConflictResolution defaultResolution, {
  int maxRetries = 3,
}) async {
  for (int attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      await syncService.performFullSync(
        defaultResolution: defaultResolution,
      );
      print('$context sync completed successfully on attempt $attempt');
      return;
    } catch (e) {
      print('$context sync failed on attempt $attempt: $e');
      
      if (attempt == maxRetries) {
        print('$context sync failed after $maxRetries attempts. User can choose to ignore or retry manually.');
        // In a real app, you might want to show a dialog to the user
        // For now, we'll just log the failure
        return;
      }
      
      // Wait before retry (exponential backoff)
      await Future.delayed(Duration(seconds: attempt * 2));
    }
  }
}

class WordDictationApp extends StatelessWidget {
  const WordDictationApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => AppStateProvider()),
        ChangeNotifierProvider(create: (_) => DictationProvider()),
        ChangeNotifierProvider(create: (_) => HistoryProvider()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return MaterialApp(
            title: '默写小助手',
            debugShowCheckedModeBanner: false,
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

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  int _currentIndex = 0;
  final OssSyncService _ossSyncService = OssSyncService();
  
  final List<Widget> _screens = [
    const HomeScreen(),
    const HistoryScreen(),
    const SettingsScreen(),
  ];
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // Perform startup sync after UI is ready
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _performStartupSync();
    });
  }
  
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      // App is being closed or paused, perform sync
      _performShutdownSync();
    }
  }
  
  Future<void> _performStartupSync() async {
    if (_ossSyncService.isSyncEnabled) {
      final resolution = await _showSyncDirectionDialog('启动时同步');
      if (resolution != null) {
        await _performSyncWithRetry(
          _ossSyncService,
          'startup',
          resolution,
        );
      }
    }
  }
  
  Future<void> _performShutdownSync() async {
    if (_ossSyncService.isSyncEnabled) {
      final resolution = await _showSyncDirectionDialog('关闭时同步');
      if (resolution != null) {
        await _performSyncWithRetry(
          _ossSyncService,
          'shutdown',
          resolution,
        );
      }
    }
  }
  
  Future<ConflictResolution?> _showSyncDirectionDialog(String title) async {
    return showDialog<ConflictResolution>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: const Text('请选择同步方向：'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('跳过'),
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
      ),
    );
  }

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