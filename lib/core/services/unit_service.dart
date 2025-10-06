import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import '../../shared/models/unit.dart';
import 'wordbook_service.dart';

class UnitService {
  static final UnitService _instance = UnitService._internal();
  factory UnitService() => _instance;
  UnitService._internal();

  Future<Database> get _db async => await DatabaseHelper.instance.database;

  /// 获取指定词书的所有单元
  Future<List<Unit>> getUnitsByWordbookId(int wordbookId) async {
    final db = await _db;
    final maps = await db.query(
      'units',
      where: 'wordbook_id = ?',
      whereArgs: [wordbookId],
      orderBy: 'name ASC',
    );
    return maps.map((map) => Unit.fromMap(map)).toList();
  }

  /// 获取指定词书的已学习单元
  Future<List<Unit>> getLearnedUnitsByWordbookId(int wordbookId) async {
    final db = await _db;
    final maps = await db.query(
      'units',
      where: 'wordbook_id = ? AND is_learned = 1',
      whereArgs: [wordbookId],
      orderBy: 'name ASC',
    );
    return maps.map((map) => Unit.fromMap(map)).toList();
  }

  /// 获取指定词书的未学习单元
  Future<List<Unit>> getUnlearnedUnitsByWordbookId(int wordbookId) async {
    final db = await _db;
    final maps = await db.query(
      'units',
      where: 'wordbook_id = ? AND is_learned = 0',
      whereArgs: [wordbookId],
      orderBy: 'name ASC',
    );
    return maps.map((map) => Unit.fromMap(map)).toList();
  }

  /// 根据ID获取单元
  Future<Unit?> getUnitById(int id) async {
    final db = await _db;
    final maps = await db.query(
      'units',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isNotEmpty) {
      return Unit.fromMap(maps.first);
    }
    return null;
  }

  /// 创建单元
  Future<int> createUnit(Unit unit) async {
    final db = await _db;
    final now = DateTime.now().millisecondsSinceEpoch;
    final unitMap = unit.toMap();
    unitMap['created_at'] = now;
    unitMap['updated_at'] = now;
    unitMap.remove('id'); // 让数据库自动生成ID
    return await db.insert('units', unitMap);
  }

  /// 更新单元
  Future<int> updateUnit(Unit unit) async {
    final db = await _db;
    final unitMap = unit.toMap();
    unitMap['updated_at'] = DateTime.now().millisecondsSinceEpoch;
    return await db.update(
      'units',
      unitMap,
      where: 'id = ?',
      whereArgs: [unit.id],
    );
  }

  /// 重命名单元，并同步更新该单元下所有单词的 category（按名称绑定场景）
  Future<void> renameUnitAndSyncWordCategories({
    required int unitId,
    required int wordbookId,
    required String oldName,
    required String newName,
  }) async {
    final db = await _db;
    await db.transaction((txn) async {
      // 更新单元名称
      await txn.update(
        'units',
        {
          'name': newName,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [unitId],
      );

      // 同步更新该词书下绑定到旧名称的单词的 category
      await txn.update(
        'words',
        {
          'category': newName,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'wordbook_id = ? AND category = ?',
        whereArgs: [wordbookId, oldName],
      );

      // 额外一致性处理：对所有 unit_id = 该单元 的单词，若 category 为空或与旧名称相同，则设置为新名称
      await txn.update(
        'words',
        {
          'category': newName,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'wordbook_id = ? AND unit_id = ? AND (category IS NULL OR category = ?)',
        whereArgs: [wordbookId, unitId, oldName],
      );
    });
  }

  /// 标记单元为已学习
  Future<int> markUnitAsLearned(int unitId) async {
    final db = await _db;
    return await db.update(
      'units',
      {
        'is_learned': 1,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [unitId],
    );
  }

  /// 标记单元为未学习
  Future<int> markUnitAsUnlearned(int unitId) async {
    final db = await _db;
    return await db.update(
      'units',
      {
        'is_learned': 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [unitId],
    );
  }

  /// 切换单元学习状态
  Future<int> toggleUnitLearnedStatus(int unitId) async {
    final unit = await getUnitById(unitId);
    if (unit == null) return 0;
    
    if (unit.isLearned) {
      return await markUnitAsUnlearned(unitId);
    } else {
      return await markUnitAsLearned(unitId);
    }
  }

  /// 删除单元（同时删除关联的单词）
  Future<int> deleteUnit(int unitId) async {
    final db = await _db;
    
    // 获取单元信息以便更新词书单词数量
    final unitResult = await db.query(
      'units',
      where: 'id = ?',
      whereArgs: [unitId],
    );
    
    if (unitResult.isEmpty) {
      return 0;
    }
    
    final wordbookId = unitResult.first['wordbook_id'] as int;
    
    // 先删除关联的例句，避免孤儿数据
    await db.rawDelete(
      'DELETE FROM example_sentences WHERE word_id IN (SELECT id FROM words WHERE unit_id = ?)',
      [unitId],
    );

    // 再删除关联的单词
    await db.delete(
      'words',
      where: 'unit_id = ?',
      whereArgs: [unitId],
    );
    
    // 再删除单元
    final result = await db.delete(
      'units',
      where: 'id = ?',
      whereArgs: [unitId],
    );
    
    // 更新词书的单词数量
    final WordbookService wordbookService = WordbookService();
    await wordbookService.updateWordbookWordCount(wordbookId);
    
    return result;
  }

  /// 更新单元的单词数量
  Future<void> updateUnitWordCount(int unitId) async {
    final db = await _db;
    
    // 计算该单元的单词数量
    final countResult = await db.rawQuery(
      'SELECT COUNT(*) as count FROM words WHERE unit_id = ?',
      [unitId],
    );
    final wordCount = countResult.first['count'] as int;
    
    // 更新单元的单词数量
    await db.update(
      'units',
      {
        'word_count': wordCount,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [unitId],
    );
  }

  /// 获取词书的学习进度统计
  Future<Map<String, int>> getWordbookLearningStats(int wordbookId) async {
    final db = await _db;
    
    final totalResult = await db.rawQuery(
      'SELECT COUNT(*) as count FROM units WHERE wordbook_id = ?',
      [wordbookId],
    );
    final total = totalResult.first['count'] as int;
    
    final learnedResult = await db.rawQuery(
      'SELECT COUNT(*) as count FROM units WHERE wordbook_id = ? AND is_learned = 1',
      [wordbookId],
    );
    final learned = learnedResult.first['count'] as int;
    
    return {
      'total': total,
      'learned': learned,
      'unlearned': total - learned,
    };
  }
}