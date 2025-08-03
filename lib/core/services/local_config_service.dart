import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart';
import 'package:flutter/foundation.dart';

class LocalConfigService {
  static LocalConfigService? _instance;
  static Map<String, dynamic>? _config;
  static String? _configPath;

  LocalConfigService._();

  static Future<LocalConfigService> getInstance() async {
    _instance ??= LocalConfigService._();
    if (_config == null) {
      await _loadConfig();
    }
    return _instance!;
  }

  static Future<void> _loadConfig() async {
    try {
      final configFile = await _getConfigFile();
      if (await configFile.exists()) {
        final content = await configFile.readAsString();
        _config = jsonDecode(content) as Map<String, dynamic>;
      } else {
        _config = <String, dynamic>{};
        await _saveConfig();
      }
    } catch (e) {
      print('Failed to load config: $e');
      _config = <String, dynamic>{};
    }
  }

  static Future<File> _getConfigFile() async {
    if (_configPath == null) {
      String appDir;
      if (kIsWeb) {
        appDir = '.';
      } else if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        // Get executable directory for desktop platforms
        final executablePath = Platform.resolvedExecutable;
        appDir = dirname(executablePath);
      } else {
        // This shouldn't happen in this context, but fallback
        appDir = '.';
      }
      _configPath = join(appDir, 'app_config.json');
    }
    return File(_configPath!);
  }

  static Future<void> _saveConfig() async {
    try {
      final configFile = await _getConfigFile();
      final content = jsonEncode(_config);
      await configFile.writeAsString(content);
    } catch (e) {
      print('Failed to save config: $e');
    }
  }

  // Theme settings
  Future<String> getThemeMode() async {
    return _config?['theme_mode'] ?? 'system';
  }

  Future<void> setThemeMode(String mode) async {
    _config!['theme_mode'] = mode;
    await _saveConfig();
  }

  Future<String> getColorScheme() async {
    return _config?['color_scheme'] ?? 'blue';
  }

  Future<void> setColorScheme(String scheme) async {
    _config!['color_scheme'] = scheme;
    await _saveConfig();
  }

  // Dictation settings
  Future<bool> getAutoPlay() async {
    return _config?['auto_play'] ?? true;
  }

  Future<void> setAutoPlay(bool enabled) async {
    _config!['auto_play'] = enabled;
    await _saveConfig();
  }

  Future<double> getPlaybackSpeed() async {
    return (_config?['playback_speed'] ?? 1.0).toDouble();
  }

  Future<void> setPlaybackSpeed(double speed) async {
    _config!['playback_speed'] = speed;
    await _saveConfig();
  }

  Future<int> getRepeatCount() async {
    return _config?['repeat_count'] ?? 2;
  }

  Future<void> setRepeatCount(int count) async {
    _config!['repeat_count'] = count;
    await _saveConfig();
  }

  Future<bool> getShowPinyin() async {
    return _config?['show_pinyin'] ?? false;
  }

  Future<void> setShowPinyin(bool enabled) async {
    _config!['show_pinyin'] = enabled;
    await _saveConfig();
  }

  Future<bool> getEnableHandwriting() async {
    return _config?['enable_handwriting'] ?? true;
  }

  Future<void> setEnableHandwriting(bool enabled) async {
    _config!['enable_handwriting'] = enabled;
    await _saveConfig();
  }

  // Study settings
  Future<int> getDailyGoal() async {
    return _config?['daily_goal'] ?? 20;
  }

  Future<void> setDailyGoal(int goal) async {
    _config!['daily_goal'] = goal;
    await _saveConfig();
  }

  Future<bool> getReminderEnabled() async {
    return _config?['reminder_enabled'] ?? false;
  }

  Future<void> setReminderEnabled(bool enabled) async {
    _config!['reminder_enabled'] = enabled;
    await _saveConfig();
  }

  Future<String> getReminderTime() async {
    return _config?['reminder_time'] ?? '20:00';
  }

  Future<void> setReminderTime(String time) async {
    _config!['reminder_time'] = time;
    await _saveConfig();
  }

  // Export/Import settings
  Future<String?> getLastExportPath() async {
    return _config?['last_export_path'];
  }

  Future<void> setLastExportPath(String path) async {
    _config!['last_export_path'] = path;
    await _saveConfig();
  }

  Future<bool> getAutoBackup() async {
    return _config?['auto_backup'] ?? false;
  }

  Future<void> setAutoBackup(bool enabled) async {
    _config!['auto_backup'] = enabled;
    await _saveConfig();
  }

  Future<int> getBackupInterval() async {
    return _config?['backup_interval'] ?? 7; // days
  }

  Future<void> setBackupInterval(int days) async {
    _config!['backup_interval'] = days;
    await _saveConfig();
  }

  // History settings
  int getHistoryLimit() {
    return _config?['history_limit'] ?? 50;
  }

  Future<void> setHistoryLimit(int limit) async {
    _config!['history_limit'] = limit;
    await _saveConfig();
  }

  // Utility methods
  Future<void> clearAllSettings() async {
    _config!.clear();
    await _saveConfig();
  }

  Future<Map<String, dynamic>> getAllSettings() async {
    return Map<String, dynamic>.from(_config ?? {});
  }

  Future<void> importSettings(Map<String, dynamic> settings) async {
    _config!.addAll(settings);
    await _saveConfig();
  }



  // Brush settings
  Future<double> getDefaultBrushSize() async {
    return (_config?['default_brush_size'] ?? 3.0).toDouble();
  }

  Future<void> setDefaultBrushSize(double size) async {
    _config!['default_brush_size'] = size;
    await _saveConfig();
  }

  // Generic setting method
  Future<void> setSetting<T>(String key, T value) async {
    _config![key] = value;
    await _saveConfig();
  }
}