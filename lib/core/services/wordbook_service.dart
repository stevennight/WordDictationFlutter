import 'dart:convert';

import '../../shared/models/wordbook.dart';
import '../../shared/models/word.dart';
import '../database/database_helper.dart';
import 'word_service.dart';

class WordbookService {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final WordService _wordService = WordService();

  /// Create a new wordbook
  Future<int> createWordbook(Wordbook wordbook) async {
    final db = await _dbHelper.database;
    return await db.insert('wordbooks', wordbook.toMap());
  }

  /// Get all wordbooks
  Future<List<Wordbook>> getAllWordbooks() async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'wordbooks',
      orderBy: 'created_at DESC',
    );
    
    return List.generate(maps.length, (i) {
      return Wordbook.fromMap(maps[i]);
    });
  }

  /// Get wordbook by ID
  Future<Wordbook?> getWordbookById(int id) async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'wordbooks',
      where: 'id = ?',
      whereArgs: [id],
    );
    
    if (maps.isNotEmpty) {
      return Wordbook.fromMap(maps.first);
    }
    return null;
  }

  /// Update wordbook
  Future<int> updateWordbook(Wordbook wordbook) async {
    final db = await _dbHelper.database;
    return await db.update(
      'wordbooks',
      wordbook.toMap(),
      where: 'id = ?',
      whereArgs: [wordbook.id],
    );
  }

  /// Delete wordbook and its words
  Future<int> deleteWordbook(int wordbookId) async {
    final db = await _dbHelper.database;
    
    // Delete in transaction to ensure data consistency
    return await db.transaction((txn) async {
      // Delete all words in this wordbook
      await txn.delete(
        'words',
        where: 'wordbook_id = ?',
        whereArgs: [wordbookId],
      );
      
      // Delete the wordbook
      return await txn.delete(
        'wordbooks',
        where: 'id = ?',
        whereArgs: [wordbookId],
      );
    });
  }

  /// Get words in a wordbook
  Future<List<Word>> getWordbookWords(int wordbookId) async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'words',
      where: 'wordbook_id = ?',
      whereArgs: [wordbookId],
      orderBy: 'created_at ASC',
    );
    
    return List.generate(maps.length, (i) {
      return Word.fromMap(maps[i]);
    });
  }

  /// Import words to a wordbook
  Future<Wordbook> importWordsToWordbook({
    required String name,
    required List<Word> words,
    String? description,
    String? originalFileName,
  }) async {
    final db = await _dbHelper.database;
    final now = DateTime.now();
    
    return await db.transaction((txn) async {
      // Create wordbook
      final wordbook = Wordbook(
        name: name,
        description: description,
        originalFileName: originalFileName,
        wordCount: words.length,
        createdAt: now,
        updatedAt: now,
      );
      
      final wordbookId = await txn.insert('wordbooks', wordbook.toMap());
      
      // Insert words with wordbook_id
      for (final word in words) {
        final wordWithBookId = word.copyWith(
          wordbookId: wordbookId,
          createdAt: now,
          updatedAt: now,
        );
        await txn.insert('words', wordWithBookId.toMap());
      }
      
      return wordbook.copyWith(id: wordbookId);
    });
  }

  /// Search wordbooks by name
  Future<List<Wordbook>> searchWordbooks(String query) async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'wordbooks',
      where: 'name LIKE ? OR description LIKE ?',
      whereArgs: ['%$query%', '%$query%'],
      orderBy: 'created_at DESC',
    );
    
    return List.generate(maps.length, (i) {
      return Wordbook.fromMap(maps[i]);
    });
  }

  /// Get wordbook count
  Future<int> getWordbookCount() async {
    final db = await _dbHelper.database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM wordbooks');
    return result.first['count'] as int;
  }

  /// Update wordbook word count (call after adding/removing words)
  Future<void> updateWordbookWordCount(int wordbookId) async {
    final db = await _dbHelper.database;
    
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM words WHERE wordbook_id = ?',
      [wordbookId],
    );
    
    final wordCount = result.first['count'] as int;
    
    await db.update(
      'wordbooks',
      {
        'word_count': wordCount,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [wordbookId],
    );
  }

  /// Update a word
  Future<int> updateWord(Word word) async {
    final db = await _dbHelper.database;
    return await db.update(
      'words',
      word.toMap(),
      where: 'id = ?',
      whereArgs: [word.id],
    );
  }

  /// Delete a word
  Future<int> deleteWord(int wordId) async {
    final db = await _dbHelper.database;
    return await db.delete(
      'words',
      where: 'id = ?',
      whereArgs: [wordId],
    );
  }

  /// Add a word to wordbook
  Future<int> addWordToWordbook(Word word) async {
    final db = await _dbHelper.database;
    return await db.insert('words', word.toMap());
  }

  /// Export a single wordbook and its words to a JSON string
  Future<String> exportSingleWordbook(int wordbookId) async {
    final wordbook = await getWordbookById(wordbookId);
    if (wordbook == null) {
      throw Exception('词书不存在');
    }

    final words = await getWordbookWords(wordbookId);
    final wordbookMap = wordbook.toMap();
    wordbookMap['words'] = words.map((w) => w.toMap()).toList();

    // Use a structured format for the final JSON
    final singleExport = {
      'version': '1.0.0',
      'createdAt': DateTime.now().toIso8601String(),
      'wordbooks': [wordbookMap],
    };

    return jsonEncode(singleExport);
  }

  /// Import and update existing wordbook or create new one
  Future<Wordbook> importAndUpdateWordbook({
    required String name,
    required List<Word> words,
    String? description,
    String? originalFileName,
  }) async {
    final db = await _dbHelper.database;
    final now = DateTime.now();
    
    return await db.transaction((txn) async {
      // Check if wordbook with same name exists
      final existingWordbooks = await txn.query(
        'wordbooks',
        where: 'name = ?',
        whereArgs: [name],
      );
      
      int wordbookId;
      Wordbook wordbook;
      
      if (existingWordbooks.isNotEmpty) {
        // Update existing wordbook
        wordbookId = existingWordbooks.first['id'] as int;
        
        // Delete all existing words in this wordbook
        await txn.delete(
          'words',
          where: 'wordbook_id = ?',
          whereArgs: [wordbookId],
        );
        
        // Update wordbook info
        wordbook = Wordbook(
          id: wordbookId,
          name: name,
          description: description,
          originalFileName: originalFileName,
          wordCount: words.length,
          createdAt: DateTime.fromMillisecondsSinceEpoch(existingWordbooks.first['created_at'] as int),
          updatedAt: now,
        );
        
        await txn.update(
          'wordbooks',
          wordbook.toMap(),
          where: 'id = ?',
          whereArgs: [wordbookId],
        );
      } else {
        // Create new wordbook
        wordbook = Wordbook(
          name: name,
          description: description,
          originalFileName: originalFileName,
          wordCount: words.length,
          createdAt: now,
          updatedAt: now,
        );
        
        wordbookId = await txn.insert('wordbooks', wordbook.toMap());
        wordbook = wordbook.copyWith(id: wordbookId);
      }
      
      // Insert new words
      for (final word in words) {
        final wordWithBookId = word.copyWith(
          wordbookId: wordbookId,
          createdAt: now,
          updatedAt: now,
        );
        await txn.insert('words', wordWithBookId.toMap());
      }
      
      return wordbook;
    });
  }

  /// Add a word (alias for addWordToWordbook)
  Future<int> addWord(Word word) async {
    return await addWordToWordbook(word);
  }
}