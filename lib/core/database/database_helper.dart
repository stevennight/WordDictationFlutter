import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _database;

  DatabaseHelper._internal();

  static DatabaseHelper get instance => _instance;

  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path;
    
    if (kIsWeb) {
      // For web platform, use in-memory database
      path = 'word_dictation.db';
    } else {
      // For desktop platforms, use application directory
      // For mobile platforms, fallback to documents directory
      String appDir;
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        // Get executable directory for desktop platforms
        final executablePath = Platform.resolvedExecutable;
        appDir = dirname(executablePath);
      } else {
        // Fallback to documents directory for mobile platforms
        final documentsDirectory = await getApplicationDocumentsDirectory();
        appDir = documentsDirectory.path;
      }
      path = join(appDir, 'word_dictation.db');
    }
    
    return await openDatabase(
      path,
      version: 6,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // Create wordbooks table
    await db.execute('''
      CREATE TABLE wordbooks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        description TEXT,
        original_file_name TEXT,
        word_count INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    // Create units table
    await db.execute('''
      CREATE TABLE units (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        description TEXT,
        wordbook_id INTEGER NOT NULL,
        word_count INTEGER NOT NULL DEFAULT 0,
        is_learned INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (wordbook_id) REFERENCES wordbooks (id)
      )
    ''');

    // Create words table
    await db.execute('''
      CREATE TABLE words (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        prompt TEXT NOT NULL,
        answer TEXT NOT NULL,
        category TEXT,
        part_of_speech TEXT,
        level TEXT,
        wordbook_id INTEGER,
        unit_id INTEGER,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (wordbook_id) REFERENCES wordbooks (id),
        FOREIGN KEY (unit_id) REFERENCES units (id)
      )
    ''');

    // Create dictation_sessions table
    await db.execute('''
      CREATE TABLE dictation_sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id TEXT UNIQUE NOT NULL,
        word_file_name TEXT,
        mode INTEGER NOT NULL,
        status INTEGER NOT NULL,
        total_words INTEGER NOT NULL,
        expected_total_words INTEGER DEFAULT 0,
        current_word_index INTEGER DEFAULT 0,
        correct_count INTEGER DEFAULT 0,
        incorrect_count INTEGER DEFAULT 0,
        start_time INTEGER NOT NULL,
        end_time INTEGER,
        is_retry_session INTEGER DEFAULT 0,
        original_session_id TEXT,
        dictation_direction INTEGER DEFAULT 0
      )
    ''');

    // Create dictation_results table
    await db.execute('''
      CREATE TABLE dictation_results (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id TEXT NOT NULL,
        word_id INTEGER NOT NULL,
        prompt TEXT NOT NULL,
        answer TEXT NOT NULL,
        is_correct INTEGER NOT NULL,
        original_image_path TEXT,
        annotated_image_path TEXT,
        word_index INTEGER NOT NULL,
        timestamp INTEGER NOT NULL,
        user_notes TEXT,
        FOREIGN KEY (session_id) REFERENCES dictation_sessions (session_id),
        FOREIGN KEY (word_id) REFERENCES words (id)
      )
    ''');

    // Create session_words table (many-to-many relationship)
    await db.execute('''
      CREATE TABLE session_words (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id TEXT NOT NULL,
        word_id INTEGER NOT NULL,
        word_order INTEGER NOT NULL,
        FOREIGN KEY (session_id) REFERENCES dictation_sessions (session_id),
        FOREIGN KEY (word_id) REFERENCES words (id)
      )
    ''');

    // Create app_settings table
    await db.execute('''
      CREATE TABLE app_settings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        key TEXT UNIQUE NOT NULL,
        value TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    // Create indexes for better performance
    await db.execute('CREATE INDEX idx_words_prompt ON words (prompt)');
    await db.execute('CREATE INDEX idx_words_answer ON words (answer)');
    await db.execute('CREATE INDEX idx_words_wordbook_id ON words (wordbook_id)');
    await db.execute('CREATE INDEX idx_words_unit_id ON words (unit_id)');
    await db.execute('CREATE INDEX idx_units_wordbook_id ON units (wordbook_id)');
    await db.execute('CREATE INDEX idx_units_name ON units (name)');
    await db.execute('CREATE INDEX idx_wordbooks_name ON wordbooks (name)');
    await db.execute('CREATE INDEX idx_sessions_start_time ON dictation_sessions (start_time)');
    await db.execute('CREATE INDEX idx_results_session_id ON dictation_results (session_id)');
    await db.execute('CREATE INDEX idx_results_word_id ON dictation_results (word_id)');
    await db.execute('CREATE INDEX idx_session_words_session_id ON session_words (session_id)');
    await db.execute('CREATE INDEX idx_settings_key ON app_settings (key)');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Handle database schema upgrades here
    if (oldVersion < 2 && newVersion >= 2) {
      // Add wordbooks table
      await db.execute('''
        CREATE TABLE wordbooks (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          description TEXT,
          original_file_name TEXT,
          word_count INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''');
      
      // Add wordbook_id column to words table
      await db.execute('ALTER TABLE words ADD COLUMN wordbook_id INTEGER');
      
      // Create indexes for new columns
      await db.execute('CREATE INDEX idx_words_wordbook_id ON words (wordbook_id)');
      await db.execute('CREATE INDEX idx_wordbooks_name ON wordbooks (name)');
    }
    
    if (oldVersion < 3 && newVersion >= 3) {
      // Add part_of_speech and level columns to words table
      await db.execute('ALTER TABLE words ADD COLUMN part_of_speech TEXT');
      await db.execute('ALTER TABLE words ADD COLUMN level TEXT');
    }
    
    if (oldVersion < 4 && newVersion >= 4) {
      // Add dictation_direction column to dictation_sessions table
      await db.execute('ALTER TABLE dictation_sessions ADD COLUMN dictation_direction INTEGER DEFAULT 0');
    }
    
    if (oldVersion < 5 && newVersion >= 5) {
      // Add expected_total_words column to dictation_sessions table
      await db.execute('ALTER TABLE dictation_sessions ADD COLUMN expected_total_words INTEGER DEFAULT 0');
    }
    
    if (oldVersion < 6 && newVersion >= 6) {
      // Create units table
      await db.execute('''
        CREATE TABLE units (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          description TEXT,
          wordbook_id INTEGER NOT NULL,
          word_count INTEGER NOT NULL DEFAULT 0,
          is_learned INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          FOREIGN KEY (wordbook_id) REFERENCES wordbooks (id)
        )
      ''');
      
      // Add unit_id column to words table
      await db.execute('ALTER TABLE words ADD COLUMN unit_id INTEGER');
      
      // Create indexes for new columns
      await db.execute('CREATE INDEX idx_words_unit_id ON words (unit_id)');
      await db.execute('CREATE INDEX idx_units_wordbook_id ON units (wordbook_id)');
      await db.execute('CREATE INDEX idx_units_name ON units (name)');
      
      // Migrate existing data: create units from existing categories
      final wordbooksResult = await db.query('wordbooks');
      for (final wordbookMap in wordbooksResult) {
        final wordbookId = wordbookMap['id'] as int;
        
        // Get distinct categories for this wordbook
        final categoriesResult = await db.rawQuery('''
          SELECT DISTINCT category FROM words 
          WHERE wordbook_id = ? AND category IS NOT NULL AND category != ''
        ''', [wordbookId]);
        
        // Create units for each category
        for (final categoryMap in categoriesResult) {
          final category = categoryMap['category'] as String;
          final now = DateTime.now().millisecondsSinceEpoch;
          
          // Count words in this category
          final countResult = await db.rawQuery('''
            SELECT COUNT(*) as count FROM words 
            WHERE wordbook_id = ? AND category = ?
          ''', [wordbookId, category]);
          final wordCount = countResult.first['count'] as int;
          
          // Insert unit
          final unitId = await db.insert('units', {
            'name': category,
            'wordbook_id': wordbookId,
            'word_count': wordCount,
            'is_learned': 0,
            'created_at': now,
            'updated_at': now,
          });
          
          // Update words to reference this unit
          await db.update(
            'words',
            {'unit_id': unitId},
            where: 'wordbook_id = ? AND category = ?',
            whereArgs: [wordbookId, category],
          );
        }
        
        // Handle words without category (create "未分类" unit)
        final uncategorizedResult = await db.rawQuery('''
          SELECT COUNT(*) as count FROM words 
          WHERE wordbook_id = ? AND (category IS NULL OR category = '')
        ''', [wordbookId]);
        final uncategorizedCount = uncategorizedResult.first['count'] as int;
        
        if (uncategorizedCount > 0) {
          final now = DateTime.now().millisecondsSinceEpoch;
          final unitId = await db.insert('units', {
            'name': '未分类',
            'wordbook_id': wordbookId,
            'word_count': uncategorizedCount,
            'is_learned': 0,
            'created_at': now,
            'updated_at': now,
          });
          
          // Update uncategorized words
          await db.update(
            'words',
            {'unit_id': unitId},
            where: 'wordbook_id = ? AND (category IS NULL OR category = ?)',
            whereArgs: [wordbookId, ''],
          );
        }
      }
    }
  }

  // Generic CRUD operations
  Future<int> insert(String table, Map<String, dynamic> values) async {
    final db = await database;
    return await db.insert(table, values);
  }

  Future<List<Map<String, dynamic>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<dynamic>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) async {
    final db = await database;
    return await db.query(
      table,
      distinct: distinct,
      columns: columns,
      where: where,
      whereArgs: whereArgs,
      groupBy: groupBy,
      having: having,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );
  }

  Future<int> update(
    String table,
    Map<String, dynamic> values, {
    String? where,
    List<dynamic>? whereArgs,
  }) async {
    final db = await database;
    return await db.update(table, values, where: where, whereArgs: whereArgs);
  }

  Future<int> delete(
    String table, {
    String? where,
    List<dynamic>? whereArgs,
  }) async {
    final db = await database;
    return await db.delete(table, where: where, whereArgs: whereArgs);
  }

  Future<List<Map<String, dynamic>>> rawQuery(
    String sql, [List<dynamic>? arguments]
  ) async {
    final db = await database;
    return await db.rawQuery(sql, arguments);
  }

  Future<int> rawInsert(String sql, [List<dynamic>? arguments]) async {
    final db = await database;
    return await db.rawInsert(sql, arguments);
  }

  Future<int> rawUpdate(String sql, [List<dynamic>? arguments]) async {
    final db = await database;
    return await db.rawUpdate(sql, arguments);
  }

  Future<int> rawDelete(String sql, [List<dynamic>? arguments]) async {
    final db = await database;
    return await db.rawDelete(sql, arguments);
  }

  // Transaction support
  Future<T> transaction<T>(Future<T> Function(Transaction txn) action) async {
    final db = await database;
    return await db.transaction(action);
  }

  // Batch operations
  Future<List<dynamic>> batch(Function(Batch batch) operations) async {
    final db = await database;
    final batch = db.batch();
    operations(batch);
    return await batch.commit();
  }

  // Database maintenance
  Future<void> vacuum() async {
    final db = await database;
    await db.execute('VACUUM');
  }

  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }

  // Get database file path
  Future<String> getDatabasePath() async {
    if (kIsWeb) {
      return 'word_dictation.db';
    } else {
      String appDir;
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        // Get executable directory for desktop platforms
        final executablePath = Platform.resolvedExecutable;
        appDir = dirname(executablePath);
      } else {
        // Fallback to documents directory for mobile platforms
        final documentsDirectory = await getApplicationDocumentsDirectory();
        appDir = documentsDirectory.path;
      }
      return join(appDir, 'word_dictation.db');
    }
  }

  // Get database file size
  Future<int> getDatabaseSize() async {
    final path = await getDatabasePath();
    final file = File(path);
    if (await file.exists()) {
      return await file.length();
    }
    return 0;
  }

  // Clear all data (for testing or reset)
  Future<void> clearAllData() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('dictation_results');
      await txn.delete('session_words');
      await txn.delete('dictation_sessions');
      await txn.delete('words');
      await txn.delete('app_settings');
    });
  }
}