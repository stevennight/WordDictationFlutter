import 'package:flutter_word_dictation/shared/models/word_explanation.dart';

import '../database/database_helper.dart';

class WordExplanationService {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  Future<WordExplanation?> getByWordId(int wordId) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'word_explanations',
      where: 'word_id = ?',
      whereArgs: [wordId],
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return WordExplanation.fromMap(rows.first);
  }

  Future<int> insert(WordExplanation explanation) async {
    return await _dbHelper.insert('word_explanations', explanation.toMap());
  }

  Future<int> upsertForWord(WordExplanation explanation) async {
    final db = await _dbHelper.database;
    return await db.transaction<int>((txn) async {
      await txn.delete('word_explanations', where: 'word_id = ?', whereArgs: [explanation.wordId]);
      return await txn.insert('word_explanations', explanation.toMap());
    });
  }

  Future<int> deleteByWordId(int wordId) async {
    final db = await _dbHelper.database;
    return await db.delete('word_explanations', where: 'word_id = ?', whereArgs: [wordId]);
  }
}