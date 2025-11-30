import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;
import '../../shared/utils/path_utils.dart';
import 'config_service.dart';

class AIDebugService {
  static AIDebugService? _instance;
  final ConfigService _configService;
  File? _currentLogFile;

  AIDebugService._(this._configService);

  static Future<AIDebugService> getInstance() async {
    if (_instance == null) {
      final config = await ConfigService.getInstance();
      _instance = AIDebugService._(config);
    }
    return _instance!;
  }

  Future<bool> get _isEnabled async => await _configService.getAIDebugLogsEnabled();

  Future<void> _initLogFile() async {
    if (_currentLogFile != null) return;
    
    try {
      final appDir = await PathUtils.getAppDirectory();
      final logDir = Directory(path.join(appDir.path, 'userdata/ai_debug_logs'));
      if (!await logDir.exists()) {
        await logDir.create(recursive: true);
      }
      
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      _currentLogFile = File('${logDir.path}/log_$timestamp.md');
      await _currentLogFile!.writeAsString('# AI Debug Log - $timestamp\n\n');
    } catch (e) {
      debugPrint('Failed to init AI debug log file: $e');
    }
  }

  Future<void> logReflection({
    required String blockName,
    required int attempt,
    required String prompt,
    required String generatedJson,
    required Map<String, dynamic>? reflectionResult,
  }) async {
    if (!await _isEnabled) return;
    await _initLogFile();

    final sb = StringBuffer();
    sb.writeln('## [$blockName] Reflection Attempt $attempt');
    sb.writeln('**Time:** ${DateFormat('HH:mm:ss').format(DateTime.now())}');
    sb.writeln('**Word:** $prompt');
    
    sb.writeln('### Generated JSON');
    sb.writeln('```json');
    sb.writeln(generatedJson);
    sb.writeln('```');

    sb.writeln('### Reflection Result');
    if (reflectionResult == null) {
      sb.writeln('✅ Validation Passed');
    } else {
      sb.writeln('❌ Validation Failed');
      final issues = reflectionResult['issues'] as List?;
      if (issues != null && issues.isNotEmpty) {
        for (var issue in issues) {
          sb.writeln('- **Field:** `${issue['field']}`');
          sb.writeln('  - **Problem:** ${issue['problem']}');
          sb.writeln('  - **Current:** `${issue['current']}`');
          sb.writeln('  - **Suggested:** `${issue['suggested']}`');
        }
      }
    }
    sb.writeln('\n---\n');

    await _appendLog(sb.toString());
  }

  Future<void> logCorrection({
    required String blockName,
    required int attempt,
    required String correctedJson,
  }) async {
    if (!await _isEnabled) return;
    await _initLogFile();

    final sb = StringBuffer();
    sb.writeln('## [$blockName] Correction Result (After Attempt $attempt)');
    sb.writeln('**Time:** ${DateFormat('HH:mm:ss').format(DateTime.now())}');
    
    sb.writeln('### Corrected JSON');
    sb.writeln('```json');
    sb.writeln(correctedJson);
    sb.writeln('```');
    sb.writeln('\n---\n');

    await _appendLog(sb.toString());
  }

  Future<void> _appendLog(String content) async {
    try {
      if (_currentLogFile != null) {
        await _currentLogFile!.writeAsString(content, mode: FileMode.append);
      }
    } catch (e) {
      debugPrint('Failed to write to AI debug log: $e');
    }
  }
  
  /// Get the path to the logs directory
  Future<String> getLogsDirectoryPath() async {
    final appDir = await PathUtils.getAppDirectory();
    return path.join(appDir.path, 'userdata/ai_debug_logs');
  }
}
