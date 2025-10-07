import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import '../../shared/utils/path_utils.dart';

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
      print('Config file path: ${configFile.path}');
      
      if (await configFile.exists()) {
        final content = await configFile.readAsString();
        print('Config file content length: ${content.length}');
        _config = jsonDecode(content) as Map<String, dynamic>;
        print('Config loaded successfully with ${_config!.length} settings');
      } else {
        print('Config file does not exist, creating new one');
        _config = <String, dynamic>{};
        await _saveConfig();
      }
    } catch (e, stackTrace) {
      print('Failed to load config: $e');
      print('Stack trace: $stackTrace');
      _config = <String, dynamic>{};
    }
  }

  static Future<File> _getConfigFile() async {
    if (_configPath == null) {
      String appDir;
      if (kIsWeb) {
        appDir = '.';
      } else {
        // 统一使用PathUtils获取应用根目录
        final appDirectory = await PathUtils.getAppDirectory();
        appDir = appDirectory.path;
      }
      _configPath = join(appDir, 'app_config.json');
    }
    return File(_configPath!);
  }

  static Future<void> _saveConfig() async {
    try {
      final configFile = await _getConfigFile();
      print('Saving config to: ${configFile.path}');
      
      // Ensure parent directory exists
      final parentDir = configFile.parent;
      if (!await parentDir.exists()) {
        print('Creating parent directory: ${parentDir.path}');
        await parentDir.create(recursive: true);
      }
      
      final content = jsonEncode(_config);
      print('Config content to save: $content');
      
      await configFile.writeAsString(content);
      print('Config saved successfully');
      
      // Verify the file was written
      if (await configFile.exists()) {
        final savedContent = await configFile.readAsString();
        print('Verification: saved content length = ${savedContent.length}');
      } else {
        print('Warning: Config file does not exist after save attempt');
      }
    } catch (e, stackTrace) {
      print('Failed to save config: $e');
      print('Stack trace: $stackTrace');
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

  // Deleted records retention settings
  int getDeletedRecordsRetentionDays() {
    return _config?['deleted_records_retention_days'] ?? 30;
  }

  Future<void> setDeletedRecordsRetentionDays(int days) async {
    _config!['deleted_records_retention_days'] = days;
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

  // Accuracy color settings
  Future<Map<String, Map<String, int>>> getAccuracyColorRanges() async {
    final accuracyConfig = _config?['accuracy_color_ranges'] as Map<String, dynamic>?;
    
    if (accuracyConfig == null) {
      // 返回默认配置
      return {
        'red': {'min': 0, 'max': 59},
        'yellow': {'min': 60, 'max': 79},
        'blue': {'min': 80, 'max': 89},
        'green': {'min': 90, 'max': 100},
      };
    }
    
    return {
      'red': {
        'min': accuracyConfig['red']?['min'] ?? 0,
        'max': accuracyConfig['red']?['max'] ?? 59,
      },
      'yellow': {
        'min': accuracyConfig['yellow']?['min'] ?? 60,
        'max': accuracyConfig['yellow']?['max'] ?? 79,
      },
      'blue': {
        'min': accuracyConfig['blue']?['min'] ?? 80,
        'max': accuracyConfig['blue']?['max'] ?? 89,
      },
      'green': {
        'min': accuracyConfig['green']?['min'] ?? 90,
        'max': accuracyConfig['green']?['max'] ?? 100,
      },
    };
  }

  Future<void> setAccuracyColorRanges(Map<String, Map<String, int>> ranges) async {
    _config!['accuracy_color_ranges'] = {
      'red': {
        'min': ranges['red']!['min'],
        'max': ranges['red']!['max'],
      },
      'yellow': {
        'min': ranges['yellow']!['min'],
        'max': ranges['yellow']!['max'],
      },
      'blue': {
        'min': ranges['blue']!['min'],
        'max': ranges['blue']!['max'],
      },
      'green': {
        'min': ranges['green']!['min'],
        'max': ranges['green']!['max'],
      },
    };
    await _saveConfig();
  }

  // AI settings
  Future<String> getAIEndpoint() async {
    return _config?['ai_endpoint'] ?? 'https://api.openai.com/v1';
  }

  Future<void> setAIEndpoint(String endpoint) async {
    _config!['ai_endpoint'] = endpoint;
    await _saveConfig();
  }

  Future<String> getAIApiKey() async {
    return _config?['ai_api_key'] ?? '';
  }

  Future<void> setAIApiKey(String key) async {
    _config!['ai_api_key'] = key;
    await _saveConfig();
  }

  Future<String> getAIModel() async {
    return _config?['ai_model'] ?? 'gpt-4o-mini';
  }

  Future<void> setAIModel(String model) async {
    _config!['ai_model'] = model;
    await _saveConfig();
  }

  // Generic setting methods
  Future<void> setSetting<T>(String key, T value) async {
    _config![key] = value;
    await _saveConfig();
  }

  Future<T?> getSetting<T>(String key) async {
    await _ensureConfigLoaded();
    final value = _config?[key];
    if (value is T) {
      return value;
    }
    return null;
  }

  static Future<void> _ensureConfigLoaded() async {
    if (_config == null) {
      await _loadConfig();
    }
  }
}
