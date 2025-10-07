import 'dart:io';

import '../../shared/models/unit.dart';
import '../../shared/models/word.dart';
import '../../shared/models/wordbook.dart';
import 'json_data_service.dart';
import 'unit_service.dart';
import 'wordbook_service.dart';
import '../database/database_helper.dart';

/// 统一的数据导入服务
/// 封装JSON导入和同步导入的读取JSON、更新数据库逻辑
class ImportDataService {
  final JsonDataService _jsonDataService = JsonDataService();
  final WordbookService _wordbookService = WordbookService();
  final UnitService _unitService = UnitService();

  /// 从JSON文件导入词书数据
  /// 支持单个词书导入和批量导入
  Future<ImportResult> importFromJsonFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return ImportResult.failure('文件不存在');
      }

      final jsonString = await file.readAsString();
      final jsonData = _jsonDataService.fromJsonString(jsonString);
      
      return await _importFromJsonData(jsonData, filePath);
    } catch (e) {
      return ImportResult.failure('导入失败: $e');
    }
  }

  /// 从JSON数据导入词书（用于同步功能）
  Future<ImportResult> importFromJsonData(Map<String, dynamic> jsonData) async {
    try {
      return await _importFromJsonData(jsonData, null);
    } catch (e) {
      return ImportResult.failure('导入失败: $e');
    }
  }

  /// 智能导入单个词书到新词书或现有词书
  Future<ImportResult> smartImportWordbook({
    required String filePath,
    required String name,
    String? description,
    int? existingWordbookId,
    String? unitName,
  }) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return ImportResult.failure('文件不存在');
      }

      final jsonString = await file.readAsString();
      final jsonData = _jsonDataService.fromJsonString(jsonString);
      
      if (!_jsonDataService.validateJsonFormat(jsonData)) {
        return ImportResult.failure('无效的JSON格式');
      }

      final wordbookInfo = _jsonDataService.extractWordbookInfo(jsonData);
      final words = wordbookInfo['words'] as List<Word>;
      final wordExamples = wordbookInfo['wordExamples'] as Map<String, List<Map<String, dynamic>>>?;
      final wordExplanations = wordbookInfo['wordExplanations'] as Map<String, Map<String, dynamic>>?;
      final units = wordbookInfo['units'] as List<Map<String, dynamic>>?;

      if (existingWordbookId != null && unitName != null) {
        // 导入到现有词书的指定单元
        return await _importToExistingWordbook(
          wordbookId: existingWordbookId,
          unitName: unitName,
          words: words,
          wordExamples: wordExamples,
          wordExplanations: wordExplanations,
        );
      } else {
        // 创建新词书或更新现有同名词书
        final wordbook = await _wordbookService.importAndUpdateWordbook(
          name: name,
          words: words,
          description: description,
          originalFileName: filePath.split('/').last.split('\\').last,
          units: units,
          wordExamples: wordExamples,
          wordExplanations: wordExplanations,
        );
        
        return ImportResult.success(
          message: '词书「${wordbook.name}」已成功导入/更新，包含 ${wordbook.wordCount} 个单词',
          data: {'wordbook': wordbook},
        );
      }
    } catch (e) {
      return ImportResult.failure('导入失败: $e');
    }
  }

  /// 提取JSON文件中的词书信息（用于预览）
  Future<Map<String, dynamic>> extractWordbookInfoFromFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('文件不存在');
    }

    final jsonString = await file.readAsString();
    final jsonData = _jsonDataService.fromJsonString(jsonString);
    
    final wordbookInfo = _jsonDataService.extractWordbookInfo(jsonData);
    wordbookInfo['originalFileName'] = filePath.split('/').last.split('\\').last;
    
    return wordbookInfo;
  }

  /// 验证JSON文件格式
  Future<bool> validateJsonFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return false;
      }

      final jsonString = await file.readAsString();
      final jsonData = _jsonDataService.fromJsonString(jsonString);
      
      return _jsonDataService.validateJsonFormat(jsonData);
    } catch (e) {
      return false;
    }
  }

  /// 内部方法：从JSON数据导入词书
  Future<ImportResult> _importFromJsonData(Map<String, dynamic> jsonData, String? filePath) async {
    if (!_jsonDataService.validateJsonFormat(jsonData)) {
      return ImportResult.failure('无效的JSON格式');
    }

    final wordbooksInfo = _jsonDataService.extractAllWordbooksInfo(jsonData);
    final List<Wordbook> importedWordbooks = [];
    
    for (final wordbookInfo in wordbooksInfo) {
      final wordbook = await _wordbookService.importAndUpdateWordbook(
        name: wordbookInfo['name'],
        words: wordbookInfo['words'],
        units: wordbookInfo['units'],
        description: wordbookInfo['description'],
        originalFileName: filePath?.split('/').last.split('\\').last ?? 
                         'import-${DateTime.now().millisecondsSinceEpoch}.json',
        wordExamples: wordbookInfo['wordExamples'] as Map<String, List<Map<String, dynamic>>>?,
      );
      importedWordbooks.add(wordbook);
    }

    final totalWords = importedWordbooks.fold<int>(0, (sum, wb) => sum + wb.wordCount);
    
    return ImportResult.success(
      message: '成功导入 ${importedWordbooks.length} 个词书，共 $totalWords 个单词',
      data: {'wordbooks': importedWordbooks},
    );
  }

  /// 内部方法：导入到现有词书的指定单元
  Future<ImportResult> _importToExistingWordbook({
    required int wordbookId,
    required String unitName,
    required List<Word> words,
    Map<String, List<Map<String, dynamic>>>? wordExamples,
    Map<String, Map<String, dynamic>>? wordExplanations,
  }) async {
    final now = DateTime.now();
    
    // 首先创建或获取单元
    final existingUnits = await _unitService.getUnitsByWordbookId(wordbookId);
    Unit? targetUnit = existingUnits.where((u) => u.name == unitName).firstOrNull;
    
    if (targetUnit == null) {
      // 创建新单元
      final newUnit = Unit(
        name: unitName,
        wordbookId: wordbookId,
        wordCount: words.length,
        isLearned: false,
        createdAt: now,
        updatedAt: now,
      );
      final unitId = await _unitService.createUnit(newUnit);
      targetUnit = newUnit.copyWith(id: unitId);
    }
    
    // 合并导入：按原文（prompt）增删改并重排顺序
    await _wordbookService.mergeUnitWordsByPrompt(
      wordbookId: wordbookId,
      unitId: targetUnit!.id!,
      unitName: unitName,
      importedWords: words,
    );

    // 写入例句：按 prompt 查到对应词ID，替换其例句
    if (wordExamples != null && wordExamples.isNotEmpty) {
      final db = await DatabaseHelper.instance.database;
      final ts = DateTime.now().millisecondsSinceEpoch;
      for (final w in words) {
        final examples = wordExamples[w.prompt];
        if (examples == null || examples.isEmpty) continue;

        final maps = await db.query(
          'words',
          columns: ['id'],
          where: 'wordbook_id = ? AND unit_id = ? AND prompt = ?',
          whereArgs: [wordbookId, targetUnit.id, w.prompt],
          limit: 1,
        );
        if (maps.isEmpty) continue;
        final wordId = maps.first['id'] as int;

        // 替换例句（写入稳定的词义文本快照 sense_text，完全不依赖索引推断）
        await db.delete('example_sentences', where: 'word_id = ?', whereArgs: [wordId]);
        final batch = db.batch();
        for (final ex in examples) {
          final senseText = (ex['senseText'] ?? '') as String;
          batch.insert('example_sentences', {
            'word_id': wordId,
            'sense_index': (ex['senseIndex'] ?? 0) as int,
            'sense_text': senseText,
            'text_plain': (ex['textPlain'] ?? '') as String,
            'text_html': (ex['textHtml'] ?? '') as String,
            'text_translation': (ex['textTranslation'] ?? '') as String,
            'source_model': ex['sourceModel'],
            'created_at': ts,
            'updated_at': ts,
          });
        }
        await batch.commit(noResult: true);
      }
    }

    // 写入词解：按 prompt 查到对应词ID，替换其词解
    if (wordExplanations != null && wordExplanations.isNotEmpty) {
      final db = await DatabaseHelper.instance.database;
      final ts = DateTime.now().millisecondsSinceEpoch;
      int parseTs(dynamic v) {
        if (v is int) return v;
        if (v is String) {
          try { return DateTime.parse(v).millisecondsSinceEpoch; } catch (_) {}
        }
        return ts;
      }
      for (final w in words) {
        final exp = wordExplanations[w.prompt];
        if (exp == null) continue;

        final maps = await db.query(
          'words',
          columns: ['id'],
          where: 'wordbook_id = ? AND unit_id = ? AND prompt = ?',
          whereArgs: [wordbookId, targetUnit.id, w.prompt],
          limit: 1,
        );
        if (maps.isEmpty) continue;
        final wordId = maps.first['id'] as int;

        // 替换词解
        await db.delete('word_explanations', where: 'word_id = ?', whereArgs: [wordId]);
        await db.insert('word_explanations', {
          'word_id': wordId,
          'html': (exp['html'] ?? '') as String,
          'source_model': exp['sourceModel'],
          'created_at': parseTs(exp['createdAt']),
          'updated_at': parseTs(exp['updatedAt']),
        });
      }
    }

    return ImportResult.success(
      message: '已按导入文件同步单元"$unitName"的单词并重排顺序',
      data: {'unit': targetUnit},
    );
  }
}

/// 导入结果类
class ImportResult {
  final bool success;
  final String message;
  final Map<String, dynamic>? data;

  ImportResult._(this.success, this.message, this.data);

  factory ImportResult.success({required String message, Map<String, dynamic>? data}) {
    return ImportResult._(true, message, data);
  }

  factory ImportResult.failure(String message) {
    return ImportResult._(false, message, null);
  }
}