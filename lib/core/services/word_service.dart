import '../../shared/models/word.dart';
import '../database/database_helper.dart';

class WordService {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  /// Get all words
  Future<List<Word>> getAllWords() async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query('words');
    
    return List.generate(maps.length, (i) {
      return Word.fromMap(maps[i]);
    });
  }

  /// Get word by ID
  Future<Word?> getWordById(int id) async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'words',
      where: 'id = ?',
      whereArgs: [id],
    );
    
    if (maps.isNotEmpty) {
      return Word.fromMap(maps.first);
    }
    return null;
  }

  /// Insert a word
  Future<int> insertWord(Word word) async {
    final db = await _dbHelper.database;
    return await db.insert('words', word.toMap());
  }

  /// Insert multiple words
  Future<void> insertWords(List<Word> words) async {
    final db = await _dbHelper.database;
    final batch = db.batch();
    
    for (final word in words) {
      batch.insert('words', word.toMap());
    }
    
    await batch.commit();
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
  Future<int> deleteWord(int id) async {
    final db = await _dbHelper.database;
    // 先删除关联例句，避免孤儿数据
    await db.delete(
      'example_sentences',
      where: 'word_id = ?',
      whereArgs: [id],
    );

    return await db.delete(
      'words',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Delete all words
  Future<int> deleteAllWords() async {
    final db = await _dbHelper.database;
    return await db.delete('words');
  }

  /// Search words by prompt or answer
  Future<List<Word>> searchWords(String query) async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'words',
      where: 'prompt LIKE ? OR answer LIKE ?',
      whereArgs: ['%$query%', '%$query%'],
    );
    
    return List.generate(maps.length, (i) {
      return Word.fromMap(maps[i]);
    });
  }

  /// Get words by category
  Future<List<Word>> getWordsByCategory(String category) async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'words',
      where: 'category = ?',
      whereArgs: [category],
    );
    
    return List.generate(maps.length, (i) {
      return Word.fromMap(maps[i]);
    });
  }

  /// Get all categories
  Future<List<String>> getAllCategories() async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.rawQuery(
      'SELECT DISTINCT category FROM words WHERE category IS NOT NULL ORDER BY category',
    );
    
    return maps.map((map) => map['category'] as String).toList();
  }

  /// Get word count
  Future<int> getWordCount() async {
    final db = await _dbHelper.database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM words');
    return result.first['count'] as int;
  }

  /// Get word count by category
  Future<int> getWordCountByCategory(String category) async {
    final db = await _dbHelper.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM words WHERE category = ?',
      [category],
    );
    return result.first['count'] as int;
  }
}