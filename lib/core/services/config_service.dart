import 'local_config_service.dart';

class ConfigService {
  static ConfigService? _instance;
  static LocalConfigService? _localConfig;

  ConfigService._();

  static Future<ConfigService> getInstance() async {
    _instance ??= ConfigService._();
    _localConfig ??= await LocalConfigService.getInstance();
    return _instance!;
  }



  // Theme settings
  Future<String> getThemeMode() async {
    return await _localConfig!.getThemeMode();
  }

  Future<void> setThemeMode(String mode) async {
    await _localConfig!.setThemeMode(mode);
  }

  Future<String> getColorScheme() async {
    return await _localConfig!.getColorScheme();
  }

  Future<void> setColorScheme(String scheme) async {
    await _localConfig!.setColorScheme(scheme);
  }

  // Dictation settings
  Future<bool> getAutoPlay() async {
    return await _localConfig!.getAutoPlay();
  }

  Future<void> setAutoPlay(bool enabled) async {
    await _localConfig!.setAutoPlay(enabled);
  }

  Future<double> getPlaybackSpeed() async {
    return await _localConfig!.getPlaybackSpeed();
  }

  Future<void> setPlaybackSpeed(double speed) async {
    await _localConfig!.setPlaybackSpeed(speed);
  }

  Future<int> getRepeatCount() async {
    return await _localConfig!.getRepeatCount();
  }

  Future<void> setRepeatCount(int count) async {
    await _localConfig!.setRepeatCount(count);
  }

  Future<bool> getShowPinyin() async {
    return await _localConfig!.getShowPinyin();
  }

  Future<void> setShowPinyin(bool enabled) async {
    await _localConfig!.setShowPinyin(enabled);
  }

  Future<bool> getEnableHandwriting() async {
    return await _localConfig!.getEnableHandwriting();
  }

  Future<void> setEnableHandwriting(bool enabled) async {
    await _localConfig!.setEnableHandwriting(enabled);
  }

  // Study settings
  Future<int> getDailyGoal() async {
    return await _localConfig!.getDailyGoal();
  }

  Future<void> setDailyGoal(int goal) async {
    await _localConfig!.setDailyGoal(goal);
  }

  Future<bool> getReminderEnabled() async {
    return await _localConfig!.getReminderEnabled();
  }

  Future<void> setReminderEnabled(bool enabled) async {
    await _localConfig!.setReminderEnabled(enabled);
  }

  Future<String> getReminderTime() async {
    return await _localConfig!.getReminderTime();
  }

  Future<void> setReminderTime(String time) async {
    await _localConfig!.setReminderTime(time);
  }

  // Export/Import settings
  Future<String?> getLastExportPath() async {
    return await _localConfig!.getLastExportPath();
  }

  Future<void> setLastExportPath(String path) async {
    await _localConfig!.setLastExportPath(path);
  }

  Future<bool> getAutoBackup() async {
    return await _localConfig!.getAutoBackup();
  }

  Future<void> setAutoBackup(bool enabled) async {
    await _localConfig!.setAutoBackup(enabled);
  }

  Future<int> getBackupInterval() async {
    return await _localConfig!.getBackupInterval();
  }

  Future<void> setBackupInterval(int days) async {
    await _localConfig!.setBackupInterval(days);
  }

  // Utility methods
  Future<void> clearAllSettings() async {
    await _localConfig!.clearAllSettings();
  }

  Future<Map<String, dynamic>> getAllSettings() async {
    return await _localConfig!.getAllSettings();
  }

  Future<void> importSettings(Map<String, dynamic> settings) async {
    await _localConfig!.importSettings(settings);
  }

  // History settings
  int getHistoryLimit() {
    return _localConfig!.getHistoryLimit();
  }

  Future<void> setHistoryLimit(int limit) async {
    await _localConfig!.setHistoryLimit(limit);
  }

  // Deleted records retention settings
  int getDeletedRecordsRetentionDays() {
    return _localConfig!.getDeletedRecordsRetentionDays();
  }

  Future<void> setDeletedRecordsRetentionDays(int days) async {
    await _localConfig!.setDeletedRecordsRetentionDays(days);
  }

  // Brush settings
  Future<double> getDefaultBrushSize() async {
    return await _localConfig!.getDefaultBrushSize();
  }

  Future<void> setDefaultBrushSize(double size) async {
    await _localConfig!.setDefaultBrushSize(size);
  }

  // Generic settings methods
  Future<T?> getSetting<T>(String key, {T? defaultValue}) async {
    final settings = await getAllSettings();
    return settings[key] as T? ?? defaultValue;
  }

  Future<void> setSetting<T>(String key, T value) async {
    await _localConfig!.setSetting(key, value);
  }
}