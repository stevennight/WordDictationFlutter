import '../database/database_helper.dart';
import '../../shared/models/example_sentence.dart';

class ExampleSentenceService {
  final DatabaseHelper _db = DatabaseHelper.instance;

  Future<List<ExampleSentence>> getExamplesByWordId(int wordId) async {
    final db = await _db.database;
    final maps = await db.query(
      'example_sentences',
      where: 'word_id = ?',
      whereArgs: [wordId],
      orderBy: 'sense_index ASC, id ASC',
    );
    return maps.map((e) => ExampleSentence.fromMap(e)).toList();
  }

  Future<int> insertExample(ExampleSentence example) async {
    final db = await _db.database;
    return await db.insert('example_sentences', example.toMap());
  }

  Future<void> insertExamples(List<ExampleSentence> examples) async {
    if (examples.isEmpty) return;
    final db = await _db.database;
    final batch = db.batch();
    for (final ex in examples) {
      batch.insert('example_sentences', ex.toMap());
    }
    await batch.commit(noResult: true);
  }

  Future<int> deleteByWordId(int wordId) async {
    final db = await _db.database;
    return await db.delete('example_sentences', where: 'word_id = ?', whereArgs: [wordId]);
  }

  Future<int> deleteById(int id) async {
    final db = await _db.database;
    return await db.delete('example_sentences', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteByWordIds(List<int> wordIds) async {
    if (wordIds.isEmpty) return 0;
    final db = await _db.database;
    final placeholders = List.filled(wordIds.length, '?').join(',');
    return await db.rawDelete('DELETE FROM example_sentences WHERE word_id IN ($placeholders)', wordIds);
  }
}