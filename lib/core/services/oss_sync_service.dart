import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_oss_aliyun/flutter_oss_aliyun.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../shared/models/oss_config.dart';
import '../../shared/models/sync_record.dart';
import '../../shared/models/word.dart';
import '../../shared/models/wordbook.dart';
import '../../shared/models/dictation_session.dart';
import '../../shared/models/dictation_result.dart';
import '../database/database_helper.dart';
import 'config_service.dart';
import 'wordbook_service.dart';
import 'word_service.dart';
import 'dictation_service.dart';

class OssSyncService {
  static final OssSyncService _instance = OssSyncService._internal();
  factory OssSyncService() => _instance;
  OssSyncService._internal();

  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final WordbookService _wordbookService = WordbookService();
  final WordService _wordService = WordService();
  final DictationService _dictationService = DictationService();
  
  OssConfig? _config;
  bool _isOnline = true;

  /// Initialize OSS sync service
  Future<void> initialize() async {
    await _loadConfig();
    await _createSyncTables();
    await _initializeOssClient();
  }

  /// Initialize OSS client
   Future<void> _initializeOssClient() async {
     if (_config?.isConfigured == true) {
       try {
         // 确保endpoint格式正确，移除多余的协议前缀
         String endpoint = _config!.endpoint!;
         if (endpoint.startsWith('http://') || endpoint.startsWith('https://')) {
           // 如果已经包含协议，移除它，因为Client.init会自动添加
           endpoint = endpoint.replaceFirst(RegExp(r'^https?://'), '');
         }
         
         Client.init(
           ossEndpoint: endpoint,
           bucketName: _config!.bucketName!,
           authGetter: () => Auth(
             accessKey: _config!.accessKeyId!,
             accessSecret: _config!.accessKeySecret!,
             expire: DateTime.now().add(const Duration(hours: 1)).toIso8601String(),
             secureToken: _config!.securityToken ?? '',
           ),
         );
       } catch (e) {
         print('Failed to initialize OSS client: $e');
       }
     }
   }

  /// Load OSS configuration
  Future<void> _loadConfig() async {
    try {
      final configService = await ConfigService.getInstance();
      final settings = await configService.getAllSettings();
      
      _config = OssConfig(
        endpoint: settings['oss_endpoint'],
        accessKeyId: settings['oss_access_key_id'],
        accessKeySecret: settings['oss_access_key_secret'],
        bucketName: settings['oss_bucket_name'],
        syncDirectory: settings['oss_sync_directory'] ?? 'word_dictation',
        enabled: settings['oss_enabled'] == true,
        lastSyncTime: settings['oss_last_sync_time'] != null
            ? DateTime.fromMillisecondsSinceEpoch(settings['oss_last_sync_time'])
            : null,
        region: settings['oss_region'],
      );
    } catch (e) {
      print('Failed to load OSS config: $e');
      _config = const OssConfig();
    }
  }

  /// Save OSS configuration
  Future<void> saveConfig(OssConfig config) async {
    try {
      final configService = await ConfigService.getInstance();
      final settings = {
        'oss_endpoint': config.endpoint,
        'oss_access_key_id': config.accessKeyId,
        'oss_access_key_secret': config.accessKeySecret,
        'oss_bucket_name': config.bucketName,
        'oss_sync_directory': config.syncDirectory,
        'oss_enabled': config.enabled,
        'oss_last_sync_time': config.lastSyncTime?.millisecondsSinceEpoch,
        'oss_region': config.region,
      };
      
      await configService.importSettings(settings);
      _config = config;
      
      // Re-initialize OSS client with new configuration
      await _initializeOssClient();
    } catch (e) {
      throw Exception('Failed to save OSS config: $e');
    }
  }

  /// Create sync-related database tables
  Future<void> _createSyncTables() async {
    final db = await _dbHelper.database;
    
    // Create sync_records table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        file_name TEXT NOT NULL,
        sync_type INTEGER NOT NULL,
        status INTEGER NOT NULL,
        start_time INTEGER NOT NULL,
        end_time INTEGER,
        error_message TEXT,
        local_path TEXT,
        remote_path TEXT,
        local_hash TEXT,
        remote_hash TEXT,
        conflict_resolution INTEGER,
        local_modified_time INTEGER,
        remote_modified_time INTEGER
      )
    ''');
    
    // Create indexes
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sync_records_file_name ON sync_records (file_name)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sync_records_status ON sync_records (status)');
  }

  /// Check if sync is enabled and configured
  bool get isSyncEnabled {
    return _config?.enabled == true && _config?.isConfigured == true;
  }

  /// Check network connectivity
  Future<bool> _checkConnectivity() async {
    try {
      final result = await http.get(Uri.parse('https://www.baidu.com')).timeout(
        const Duration(seconds: 5),
      );
      _isOnline = result.statusCode == 200;
      return _isOnline;
    } catch (e) {
      _isOnline = false;
      return false;
    }
  }

  /// Perform full sync (called on app startup/shutdown)
  Future<List<SyncRecord>> performFullSync({
    ConflictResolution defaultResolution = ConflictResolution.manual,
  }) async {
    if (!isSyncEnabled) {
      throw Exception('OSS sync is not enabled or configured');
    }

    if (!await _checkConnectivity()) {
      throw Exception('No internet connection available');
    }

    final syncRecords = <SyncRecord>[];
    
    try {
      // Sync configurations
      final configRecord = await _syncConfigurations(defaultResolution);
      if (configRecord != null) {
        syncRecords.add(configRecord);
        await saveSyncRecord(configRecord);
      }
      
      // Sync database file
      final dbRecord = await _syncDatabase(defaultResolution);
      if (dbRecord != null) {
        syncRecords.add(dbRecord);
        await saveSyncRecord(dbRecord);
      }
      
      // Update last sync time
      if (_config != null) {
        await saveConfig(_config!.copyWith(lastSyncTime: DateTime.now()));
      }
      
      return syncRecords;
    } catch (e) {
      throw Exception('Sync failed: $e');
    }
  }

  /// Sync configurations
  Future<SyncRecord?> _syncConfigurations(ConflictResolution defaultResolution) async {
    const fileName = 'app_config.json';
    final startTime = DateTime.now();
    
    try {
      // Export local configurations
      final localConfig = await _exportLocalConfigurations();
      final localData = jsonEncode(localConfig);
      final localHash = _calculateHash(localData);
      
      // Check remote file
      final remotePath = '${_config!.syncDirectory}/config/$fileName';
      final remoteData = await _downloadFile(remotePath);
      
      if (remoteData == null) {
        // No remote file, upload local
        await _uploadFile(remotePath, localData);
        return SyncRecord(
          fileName: fileName,
          syncType: SyncType.upload,
          status: SyncStatus.success,
          startTime: startTime,
          endTime: DateTime.now(),
          localPath: 'local_config',
          remotePath: remotePath,
          localHash: localHash,
        );
      }
      
      final remoteHash = _calculateHash(remoteData);
      
      if (localHash == remoteHash) {
        // No changes
        return null;
      }
      
      // Check if there are meaningful differences (not just timestamps)
      if (!_hasMeaningfulDifferences(localData, remoteData)) {
        // Only timestamp differences, no real conflict
        print('Only timestamp differences detected for $fileName, skipping conflict');
        return null;
      }
      
      // Handle real conflict
      return await _handleConfigConflict(
        fileName,
        localData,
        remoteData,
        localHash,
        remoteHash,
        remotePath,
        defaultResolution,
        startTime,
      );
    } catch (e) {
      return SyncRecord(
        fileName: fileName,
        syncType: SyncType.bidirectional,
        status: SyncStatus.failed,
        startTime: startTime,
        endTime: DateTime.now(),
        errorMessage: e.toString(),
      );
    }
  }

  /// Handle configuration conflict
  Future<SyncRecord> _handleConfigConflict(
    String fileName,
    String localData,
    String remoteData,
    String localHash,
    String remoteHash,
    String remotePath,
    ConflictResolution resolution,
    DateTime startTime,
  ) async {
    if (resolution == ConflictResolution.manual) {
      return SyncRecord(
        fileName: fileName,
        syncType: SyncType.bidirectional,
        status: SyncStatus.conflict,
        startTime: startTime,
        localHash: localHash,
        remoteHash: remoteHash,
        remotePath: remotePath,
      );
    }
    
    if (resolution == ConflictResolution.ignore) {
      return SyncRecord(
        fileName: fileName,
        syncType: SyncType.bidirectional,
        status: SyncStatus.skipped,
        startTime: startTime,
        endTime: DateTime.now(),
        localHash: localHash,
        remoteHash: remoteHash,
        remotePath: remotePath,
        conflictResolution: resolution,
        errorMessage: 'Sync skipped by user',
      );
    }
    
    if (resolution == ConflictResolution.useLocal) {
      // 以本地为准：上传本地内容覆盖远程
      await _uploadFile(remotePath, localData);
      return SyncRecord(
        fileName: fileName,
        syncType: SyncType.upload,
        status: SyncStatus.success,
        startTime: startTime,
        endTime: DateTime.now(),
        localHash: localHash,
        remotePath: remotePath,
        conflictResolution: resolution,
      );
    } else {
      // 以远程为准：下载远程内容覆盖本地
      await _importRemoteConfigurations(jsonDecode(remoteData));
      return SyncRecord(
        fileName: fileName,
        syncType: SyncType.download,
        status: SyncStatus.success,
        startTime: startTime,
        endTime: DateTime.now(),
        remoteHash: remoteHash,
        remotePath: remotePath,
        conflictResolution: resolution,
      );
    }
  }

  /// Sync database file
  Future<SyncRecord?> _syncDatabase(ConflictResolution defaultResolution) async {
    const fileName = 'word_dictation.db';
    final startTime = DateTime.now();
    
    try {
      // Get database file path
      final dbPath = await _dbHelper.getDatabasePath();
      final dbFile = File(dbPath);
      
      if (!await dbFile.exists()) {
        throw Exception('Database file not found');
      }
      
      // Read database file as bytes and convert to base64
      final dbBytes = await dbFile.readAsBytes();
      final localData = base64Encode(dbBytes);
      final localHash = _calculateHash(localData);
      
      // Check remote file
      final remotePath = '${_config!.syncDirectory}/database/$fileName';
      final remoteData = await _downloadFile(remotePath);
      
      if (remoteData == null) {
        // No remote file, upload local
        await _uploadFile(remotePath, localData);
        return SyncRecord(
          fileName: fileName,
          syncType: SyncType.upload,
          status: SyncStatus.success,
          startTime: startTime,
          endTime: DateTime.now(),
          localPath: dbPath,
          remotePath: remotePath,
          localHash: localHash,
        );
      }
      
      final remoteHash = _calculateHash(remoteData);
      
      if (localHash == remoteHash) {
        // No changes
        return null;
      }
      
      // Handle conflict
      return await _handleDatabaseConflict(
        fileName,
        localData,
        remoteData,
        localHash,
        remoteHash,
        remotePath,
        defaultResolution,
        startTime,
        dbPath,
      );
    } catch (e) {
      return SyncRecord(
        fileName: fileName,
        syncType: SyncType.bidirectional,
        status: SyncStatus.failed,
        startTime: startTime,
        endTime: DateTime.now(),
        errorMessage: e.toString(),
      );
    }
  }

  /// Handle database conflict
  Future<SyncRecord> _handleDatabaseConflict(
    String fileName,
    String localData,
    String remoteData,
    String localHash,
    String remoteHash,
    String remotePath,
    ConflictResolution resolution,
    DateTime startTime,
    String dbPath,
  ) async {
    if (resolution == ConflictResolution.manual) {
      return SyncRecord(
        fileName: fileName,
        syncType: SyncType.bidirectional,
        status: SyncStatus.conflict,
        startTime: startTime,
        localHash: localHash,
        remoteHash: remoteHash,
        remotePath: remotePath,
        localPath: dbPath,
      );
    }
    
    if (resolution == ConflictResolution.ignore) {
      return SyncRecord(
        fileName: fileName,
        syncType: SyncType.bidirectional,
        status: SyncStatus.skipped,
        startTime: startTime,
        endTime: DateTime.now(),
        localHash: localHash,
        remoteHash: remoteHash,
        remotePath: remotePath,
        conflictResolution: resolution,
        errorMessage: 'Sync skipped by user',
      );
    }
    
    if (resolution == ConflictResolution.useLocal) {
      // 以本地为准：上传本地内容覆盖远程
      await _uploadFile(remotePath, localData);
      return SyncRecord(
        fileName: fileName,
        syncType: SyncType.upload,
        status: SyncStatus.success,
        startTime: startTime,
        endTime: DateTime.now(),
        localHash: localHash,
        remotePath: remotePath,
        conflictResolution: resolution,
      );
    } else {
      // 以远程为准：下载远程内容覆盖本地
      await _restoreDatabaseFromRemote(remoteData, dbPath);
      return SyncRecord(
        fileName: fileName,
        syncType: SyncType.download,
        status: SyncStatus.success,
        startTime: startTime,
        endTime: DateTime.now(),
        remoteHash: remoteHash,
        remotePath: remotePath,
        conflictResolution: resolution,
      );
    }
  }

  // Dictation records sync methods removed due to large file sizes

  // Session conflict handling removed with dictation sync

  /// Export local configurations
  Future<Map<String, dynamic>> _exportLocalConfigurations() async {
    final configService = await ConfigService.getInstance();
    return await configService.getAllSettings();
  }

  /// Import remote configurations
  Future<void> _importRemoteConfigurations(Map<String, dynamic> remoteConfig) async {
    final configService = await ConfigService.getInstance();
    await configService.importSettings(remoteConfig);
  }



  /// Restore database from remote data
  Future<void> _restoreDatabaseFromRemote(String remoteData, String dbPath) async {
    try {
      // Close current database connection
      await _dbHelper.close();
      
      // Decode base64 data to bytes
      final dbBytes = base64Decode(remoteData);
      
      // Write to database file
      final dbFile = File(dbPath);
      await dbFile.writeAsBytes(dbBytes);
      
      // Reinitialize database connection
      await _dbHelper.database;
    } catch (e) {
      throw Exception('Failed to restore database: $e');
    }
  }

  // Dictation session import/export methods removed

  /// Upload file to OSS
  Future<void> _uploadFile(String remotePath, String content) async {
    if (_config?.isConfigured != true) {
      throw Exception('OSS not configured');
    }
    
    try {
      // Re-initialize OSS client to ensure fresh credentials
      await _initializeOssClient();
      
      final bytes = Uint8List.fromList(utf8.encode(content));
      await Client().putObject(
        bytes,
        remotePath,
        option: PutRequestOption(
          override: true,
          onSendProgress: (count, total) {
            print('Upload progress: $count/$total bytes');
          },
        ),
      );
      print('Successfully uploaded to $remotePath: ${content.length} bytes');
    } catch (e) {
      print('Failed to upload file $remotePath: $e');
      throw Exception('Upload failed: $e');
    }
  }

  /// Download file from OSS
  Future<String?> _downloadFile(String remotePath) async {
    if (_config?.isConfigured != true) {
      throw Exception('OSS not configured');
    }
    
    try {
      // Re-initialize OSS client to ensure fresh credentials
      await _initializeOssClient();
      
      // Check if file exists first
      final exists = await Client().doesObjectExist(remotePath);
      if (!exists) {
        print('File does not exist: $remotePath');
        return null;
      }
      
      final response = await Client().getObject(remotePath);
      if (response.statusCode == 200 && response.data != null) {
        final content = utf8.decode(response.data);
        print('Successfully downloaded from $remotePath: ${content.length} bytes');
        return content;
      } else {
        print('Failed to download file $remotePath: HTTP ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Failed to download file $remotePath: $e');
      return null;
    }
  }

  /// Calculate hash for content with normalization
  String _calculateHash(String content) {
    // Normalize content to avoid false conflicts due to formatting differences
    final normalizedContent = content
        .replaceAll(RegExp(r'\s+'), ' ') // Normalize whitespace
        .replaceAll(RegExp(r'"createdAt":\s*"[^"]*"'), '"createdAt":"normalized"') // Normalize timestamps
        .replaceAll(RegExp(r'"updatedAt":\s*"[^"]*"'), '"updatedAt":"normalized"')
        .replaceAll(RegExp(r'"lastSyncTime":\s*"[^"]*"'), '"lastSyncTime":"normalized"')
        .trim();
    
    final bytes = utf8.encode(normalizedContent);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
  
  /// Check if content has meaningful differences (not just timestamp changes)
  bool _hasMeaningfulDifferences(String localContent, String remoteContent) {
    try {
      final localJson = jsonDecode(localContent) as Map<String, dynamic>;
      final remoteJson = jsonDecode(remoteContent) as Map<String, dynamic>;
      
      // Remove timestamp fields for comparison
      final localCopy = Map<String, dynamic>.from(localJson);
      final remoteCopy = Map<String, dynamic>.from(remoteJson);
      
      _removeTimestampFields(localCopy);
      _removeTimestampFields(remoteCopy);
      
      // Compare the content without timestamps
      return jsonEncode(localCopy) != jsonEncode(remoteCopy);
    } catch (e) {
      // If JSON parsing fails, fall back to string comparison
      return localContent.trim() != remoteContent.trim();
    }
  }
  
  /// Remove timestamp fields from JSON for comparison
  void _removeTimestampFields(Map<String, dynamic> json) {
    json.remove('createdAt');
    json.remove('updatedAt');
    json.remove('lastSyncTime');
    json.remove('startTime');
    json.remove('endTime');
    
    // Recursively remove from nested objects
    json.forEach((key, value) {
      if (value is Map<String, dynamic>) {
        _removeTimestampFields(value);
      } else if (value is List) {
        for (var item in value) {
          if (item is Map<String, dynamic>) {
            _removeTimestampFields(item);
          }
        }
      }
    });
  }

  /// Get sync records
  Future<List<SyncRecord>> getSyncRecords({int limit = 50}) async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      'sync_records',
      orderBy: 'start_time DESC',
      limit: limit,
    );
    
    return maps.map((map) => SyncRecord.fromMap(map)).toList();
  }

  /// Save sync record
  Future<int> saveSyncRecord(SyncRecord record) async {
    final db = await _dbHelper.database;
    return await db.insert('sync_records', record.toMap());
  }

  /// Update sync record
  Future<int> updateSyncRecord(SyncRecord record) async {
    final db = await _dbHelper.database;
    return await db.update(
      'sync_records',
      record.toMap(),
      where: 'id = ?',
      whereArgs: [record.id],
    );
  }

  /// Clear old sync records
  Future<void> clearOldSyncRecords({int keepDays = 30}) async {
    final db = await _dbHelper.database;
    final cutoffTime = DateTime.now().subtract(Duration(days: keepDays));
    
    await db.delete(
      'sync_records',
      where: 'start_time < ?',
      whereArgs: [cutoffTime.millisecondsSinceEpoch],
    );
  }

  // Clearing methods removed - conflicts now handled by individual file sync

  /// Get current configuration
  OssConfig? get config => _config;

  /// Check if online
  bool get isOnline => _isOnline;
}