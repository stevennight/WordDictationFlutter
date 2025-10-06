import 'package:flutter_word_dictation/core/services/unit_service.dart';
import 'package:sqflite/sqflite.dart';

import '../../shared/models/word.dart';
import '../../shared/models/wordbook.dart';
import '../database/database_helper.dart';
import 'json_data_service.dart';

class WordbookService {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

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
      // 删除该词书下所有单词的例句
      await txn.rawDelete(
        'DELETE FROM example_sentences WHERE word_id IN (SELECT id FROM words WHERE wordbook_id = ?)',
        [wordbookId],
      );
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

  /// Get words from unlearned units in a wordbook
  Future<List<Word>> getWordbookUnlearnedWords(int wordbookId) async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.rawQuery(
      '''
      SELECT w.* FROM words w
      INNER JOIN units u ON w.unit_id = u.id
      WHERE w.wordbook_id = ? AND u.is_learned = 0
      ORDER BY w.created_at ASC
      ''',
      [wordbookId],
    );
    
    return List.generate(maps.length, (i) {
      return Word.fromMap(maps[i]);
    });
  }

  /// Get words from learned units in a wordbook
  Future<List<Word>> getWordbookLearnedWords(int wordbookId) async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.rawQuery(
      '''
      SELECT w.* FROM words w
      INNER JOIN units u ON w.unit_id = u.id
      WHERE w.wordbook_id = ? AND u.is_learned = 1
      ORDER BY w.created_at ASC
      ''',
      [wordbookId],
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

  /// Merge words into a unit by prompt (original word text).
  ///
  /// Behavior:
  /// - Delete words that are NOT present in the imported list (by `prompt`).
  /// - Add words that are NEW in the imported list.
  /// - For words present in both, update fields provided by import (answer/category/part_of_speech/level)
  ///   and preserve any existing fields when the import does not provide them.
  /// - Reorder words to match the imported list order by re-sequencing `created_at` timestamps.
  Future<void> mergeUnitWordsByPrompt({
    required int wordbookId,
    required int unitId,
    required String unitName,
    required List<Word> importedWords,
  }) async {
    final db = await _dbHelper.database;

    await db.transaction((txn) async {
      // Load existing words in the unit
      final existingMaps = await txn.query(
        'words',
        where: 'unit_id = ?',
        whereArgs: [unitId],
      );

      final Map<String, Map<String, dynamic>> existingByPrompt = {
        for (final m in existingMaps) (m['prompt'] as String): m,
      };

      // Build imported prompt list (keeps order)
      final List<String> importedPrompts = importedWords.map((w) => w.prompt).toList();

      // Delete words that are not in imported list
      for (final m in existingMaps) {
        final prompt = m['prompt'] as String;
        if (!importedPrompts.contains(prompt)) {
          await txn.delete('words', where: 'id = ?', whereArgs: [m['id']]);
        }
      }

      // Upsert and reorder according to imported list
      final baseTime = DateTime.now().millisecondsSinceEpoch;
      for (int i = 0; i < importedWords.length; i++) {
        final imported = importedWords[i];
        final existing = existingByPrompt[imported.prompt];
        final ts = baseTime + i; // ensure ascending order

        if (existing != null) {
          // Update only provided fields; preserve others
          final Map<String, Object?> updateMap = {
            'answer': imported.answer,
            'category': unitName,
            'part_of_speech': imported.partOfSpeech ?? existing['part_of_speech'],
            'level': imported.level ?? existing['level'],
            'updated_at': ts,
            'created_at': ts, // use created_at to reflect new order
            'wordbook_id': wordbookId,
            'unit_id': unitId,
          };

          await txn.update(
            'words',
            updateMap,
            where: 'id = ?',
            whereArgs: [existing['id']],
          );
        } else {
          // Insert new
          final Map<String, Object?> insertMap = {
            'prompt': imported.prompt,
            'answer': imported.answer,
            'category': unitName,
            'part_of_speech': imported.partOfSpeech,
            'level': imported.level,
            'wordbook_id': wordbookId,
            'unit_id': unitId,
            'created_at': ts,
            'updated_at': ts,
          };
          await txn.insert('words', insertMap);
        }
      }
    });

    // Update counts
    final unitService = UnitService();
    await unitService.updateUnitWordCount(unitId);
    await updateWordbookWordCount(wordbookId);
  }

  /// Export a single wordbook and its words to a JSON string
  Future<String> exportSingleWordbook(int wordbookId) async {
    final jsonDataService = JsonDataService();
    final jsonData = await jsonDataService.exportSingleWordbook(wordbookId);
    return jsonDataService.toJsonString(jsonData);
  }

  /// Import and update existing wordbook or create new one
  Future<Wordbook> importAndUpdateWordbook({
    required String name,
    required List<Word> words,
    String? description,
    String? originalFileName,
    List<Map<String, dynamic>>? units,
    Map<String, List<Map<String, dynamic>>>? wordExamples,
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
        
        // Delete all existing words and units in this wordbook
        await txn.delete(
          'words',
          where: 'wordbook_id = ?',
          whereArgs: [wordbookId],
        );
        await txn.delete(
          'units',
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
      
      // Import units if provided
      final Map<String, int> unitNameToIdMap = {};
      if (units != null && units.isNotEmpty) {
        for (final unitData in units) {
          final unitMap = Map<String, dynamic>.from(unitData);
          unitMap['wordbook_id'] = wordbookId;
          unitMap['created_at'] = now.millisecondsSinceEpoch;
          unitMap['updated_at'] = now.millisecondsSinceEpoch;
          unitMap.remove('id'); // 让数据库自动生成ID
          
          final unitId = await txn.insert('units', unitMap);
          unitNameToIdMap[unitData['name']] = unitId;
        }
      }
      
      // Insert new words
      for (final word in words) {
        final wordWithBookId = word.copyWith(
          wordbookId: wordbookId,
          createdAt: now,
          updatedAt: now,
        );
        
        // 如果单词有category且对应的单元存在，设置unit_id
        if (word.category != null && unitNameToIdMap.containsKey(word.category)) {
          final wordMap = wordWithBookId.toMap();
          wordMap['unit_id'] = unitNameToIdMap[word.category];
          await txn.insert('words', wordMap);
        } else {
          await txn.insert('words', wordWithBookId.toMap());
        }

        // 插入例句（按 prompt 关联）
        final examples = wordExamples?[word.prompt];
        if (examples != null && examples.isNotEmpty) {
          // 获取刚插入/更新后的该词的ID
          final insertedWordMaps = await txn.query(
            'words',
            columns: ['id'],
            where: 'wordbook_id = ? AND prompt = ?',
            whereArgs: [wordbookId, word.prompt],
            orderBy: 'created_at DESC',
            limit: 1,
          );
          if (insertedWordMaps.isNotEmpty) {
            final wordId = insertedWordMaps.first['id'] as int;
            final ts = now.millisecondsSinceEpoch;
            for (final ex in examples) {
              final map = {
                'word_id': wordId,
                'sense_index': (ex['senseIndex'] ?? 0) as int,
                'text_plain': (ex['textPlain'] ?? '') as String,
                'text_html': (ex['textHtml'] ?? '') as String,
                'text_translation': (ex['textTranslation'] ?? '') as String,
                'source_model': ex['sourceModel'],
                'created_at': ts,
                'updated_at': ts,
              };
              await txn.insert('example_sentences', map);
            }
          }
        }
      }
      
      // 如果没有提供单元数据，自动为旧格式数据创建单元
      if (units == null || units.isEmpty) {
        await _createUnitsFromCategories(wordbookId, txn);
      }
      
      return wordbook;
    });
  }

  /// 为词书自动创建单元（基于单词的category字段）
  Future<void> _createUnitsFromCategories(int wordbookId, [Transaction? txn]) async {
    final db = txn ?? await _dbHelper.database;
    
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

  /// Add a word (alias for addWordToWordbook)
  Future<int> addWord(Word word) async {
    return await addWordToWordbook(word);
  }
}