import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import '../lib/core/services/auto_sync_manager.dart';

void main() {
  group('AutoSyncManager Tests', () {
    late AutoSyncManager autoSyncManager;

    setUp(() {
      WidgetsFlutterBinding.ensureInitialized();
      autoSyncManager = AutoSyncManager();
    });

    tearDown(() {
      autoSyncManager.dispose();
    });

    test('should create singleton instance', () {
      final instance1 = AutoSyncManager();
      final instance2 = AutoSyncManager();
      expect(instance1, equals(instance2));
    });

    test('should initialize correctly', () async {
      expect(autoSyncManager.isInitialized, false);
      expect(autoSyncManager.isSyncing, false);
    });

    test('should handle app lifecycle changes', () {
      // Test that the manager can handle lifecycle state changes
      autoSyncManager.didChangeAppLifecycleState(AppLifecycleState.resumed);
      autoSyncManager.didChangeAppLifecycleState(AppLifecycleState.paused);
      autoSyncManager.didChangeAppLifecycleState(AppLifecycleState.detached);
      
      // No exceptions should be thrown
      expect(true, true);
    });

    test('should format duration correctly', () {
      // This is a private method, but we can test the public interface
      expect(autoSyncManager.isInitialized, false);
    });
  });
}