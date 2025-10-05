import 'dart:io';

import '../../shared/models/unit.dart';
import '../../shared/models/word.dart';
import '../../shared/models/wordbook.dart';
import 'json_data_service.dart';
import 'unit_service.dart';
import 'wordbook_service.dart';

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
      final units = wordbookInfo['units'] as List<Map<String, dynamic>>?;

      if (existingWordbookId != null && unitName != null) {
        // 导入到现有词书的指定单元
        return await _importToExistingWordbook(
          wordbookId: existingWordbookId,
          unitName: unitName,
          words: words,
        );
      } else {
        // 创建新词书或更新现有同名词书
        final wordbook = await _wordbookService.importAndUpdateWordbook(
          name: name,
          words: words,
          description: description,
          originalFileName: filePath.split('/').last.split('\\').last,
          units: units,
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
    
    // 为单词设置单元ID、单元名称和词书ID
    final wordsWithUnit = words.map((word) => word.copyWith(
      unitId: targetUnit!.id,
      category: unitName,
      wordbookId: wordbookId,
      createdAt: now,
      updatedAt: now,
    )).toList();

    // 保存单词到数据库
    for (final word in wordsWithUnit) {
      await _wordbookService.addWordToWordbook(word);
    }

    // 更新单元的单词数量
    await _unitService.updateUnitWordCount(targetUnit.id!);
    
    // 更新词书的单词数量
    await _wordbookService.updateWordbookWordCount(wordbookId);

    return ImportResult.success(
      message: '成功添加 ${words.length} 个单词到单元"$unitName"',
      data: {'unit': targetUnit, 'wordsCount': words.length},
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