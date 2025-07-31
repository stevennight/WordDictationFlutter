import 'package:shared_preferences/shared_preferences.dart';

class ConfigService {
  static ConfigService? _instance;
  static SharedPreferences? _prefs;

  ConfigService._();

  static Future<ConfigService> getInstance() async {
    _instance ??= ConfigService._();
    _prefs ??= await SharedPreferences.getInstance();
    return _instance!;
  }

  // Theme settings
  static const String _themeKey = 'theme_mode';
  static const String _colorSchemeKey = 'color_scheme';
  
  // Dictation settings
  static const String _autoPlayKey = 'auto_play';
  static const String _playbackSpeedKey = 'playback_speed';
  static const String _repeatCountKey = 'repeat_count';
  static const String _showPinyinKey = 'show_pinyin';
  static const String _enableHandwritingKey = 'enable_handwriting';
  
  // Study settings
  static const String _dailyGoalKey = 'daily_goal';
  static const String _reminderEnabledKey = 'reminder_enabled';
  static const String _reminderTimeKey = 'reminder_time';
  
  // Export/Import settings
  static const String _lastExportPathKey = 'last_export_path';
  static const String _autoBackupKey = 'auto_backup';
  static const String _backupIntervalKey = 'backup_interval';

  // Theme settings
  Future<String> getThemeMode() async {
    return _prefs?.getString(_themeKey) ?? 'system';
  }

  Future<void> setThemeMode(String mode) async {
    await _prefs?.setString(_themeKey, mode);
  }

  Future<String> getColorScheme() async {
    return _prefs?.getString(_colorSchemeKey) ?? 'blue';
  }

  Future<void> setColorScheme(String scheme) async {
    await _prefs?.setString(_colorSchemeKey, scheme);
  }

  // Dictation settings
  Future<bool> getAutoPlay() async {
    return _prefs?.getBool(_autoPlayKey) ?? true;
  }

  Future<void> setAutoPlay(bool enabled) async {
    await _prefs?.setBool(_autoPlayKey, enabled);
  }

  Future<double> getPlaybackSpeed() async {
    return _prefs?.getDouble(_playbackSpeedKey) ?? 1.0;
  }

  Future<void> setPlaybackSpeed(double speed) async {
    await _prefs?.setDouble(_playbackSpeedKey, speed);
  }

  Future<int> getRepeatCount() async {
    return _prefs?.getInt(_repeatCountKey) ?? 2;
  }

  Future<void> setRepeatCount(int count) async {
    await _prefs?.setInt(_repeatCountKey, count);
  }

  Future<bool> getShowPinyin() async {
    return _prefs?.getBool(_showPinyinKey) ?? true;
  }

  Future<void> setShowPinyin(bool enabled) async {
    await _prefs?.setBool(_showPinyinKey, enabled);
  }

  Future<bool> getEnableHandwriting() async {
    return _prefs?.getBool(_enableHandwritingKey) ?? false;
  }

  Future<void> setEnableHandwriting(bool enabled) async {
    await _prefs?.setBool(_enableHandwritingKey, enabled);
  }

  // Study settings
  Future<int> getDailyGoal() async {
    return _prefs?.getInt(_dailyGoalKey) ?? 20;
  }

  Future<void> setDailyGoal(int goal) async {
    await _prefs?.setInt(_dailyGoalKey, goal);
  }

  Future<bool> getReminderEnabled() async {
    return _prefs?.getBool(_reminderEnabledKey) ?? false;
  }

  Future<void> setReminderEnabled(bool enabled) async {
    await _prefs?.setBool(_reminderEnabledKey, enabled);
  }

  Future<String> getReminderTime() async {
    return _prefs?.getString(_reminderTimeKey) ?? '20:00';
  }

  Future<void> setReminderTime(String time) async {
    await _prefs?.setString(_reminderTimeKey, time);
  }

  // Export/Import settings
  Future<String?> getLastExportPath() async {
    return _prefs?.getString(_lastExportPathKey);
  }

  Future<void> setLastExportPath(String path) async {
    await _prefs?.setString(_lastExportPathKey, path);
  }

  Future<bool> getAutoBackup() async {
    return _prefs?.getBool(_autoBackupKey) ?? false;
  }

  Future<void> setAutoBackup(bool enabled) async {
    await _prefs?.setBool(_autoBackupKey, enabled);
  }

  Future<int> getBackupInterval() async {
    return _prefs?.getInt(_backupIntervalKey) ?? 7; // days
  }

  Future<void> setBackupInterval(int days) async {
    await _prefs?.setInt(_backupIntervalKey, days);
  }

  // Utility methods
  Future<void> clearAllSettings() async {
    await _prefs?.clear();
  }

  Future<Map<String, dynamic>> getAllSettings() async {
    final keys = _prefs?.getKeys() ?? <String>{};
    final settings = <String, dynamic>{};
    
    for (final key in keys) {
      final value = _prefs?.get(key);
      if (value != null) {
        settings[key] = value;
      }
    }
    
    return settings;
  }

  Future<void> importSettings(Map<String, dynamic> settings) async {
    for (final entry in settings.entries) {
      final key = entry.key;
      final value = entry.value;
      
      if (value is String) {
        await _prefs?.setString(key, value);
      } else if (value is int) {
        await _prefs?.setInt(key, value);
      } else if (value is double) {
        await _prefs?.setDouble(key, value);
      } else if (value is bool) {
        await _prefs?.setBool(key, value);
      } else if (value is List<String>) {
        await _prefs?.setStringList(key, value);
      }
    }
  }
}