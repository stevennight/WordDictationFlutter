import 'dart:convert';

import '../../shared/models/word.dart';
import 'example_sentence_service.dart';
import 'unit_service.dart';
import 'wordbook_service.dart';

/// 通用的JSON数据处理服务
/// 用于统一处理导出、导入和同步功能的JSON格式
class JsonDataService {
  static const String currentVersion = '2.0.0';
  
  final WordbookService _wordbookService = WordbookService();
  final UnitService _unitService = UnitService();
  final ExampleSentenceService _exampleService = ExampleSentenceService();

  /// 导出单个词书为JSON格式
  Future<Map<String, dynamic>> exportSingleWordbook(int wordbookId) async {
    final wordbook = await _wordbookService.getWordbookById(wordbookId);
    if (wordbook == null) {
      throw Exception('词书不存在');
    }

    final words = await _wordbookService.getWordbookWords(wordbookId);
    final units = await _unitService.getUnitsByWordbookId(wordbookId);
    
    final wordbookMap = wordbook.toMap();
    // 每个词附加 examples 数组
    wordbookMap['words'] = await Future.wait(words.map((w) async {
      final map = w.toMap();
      if (w.id != null) {
        final examples = await _exampleService.getExamplesByWordId(w.id!);
        map['examples'] = examples
            .map((ex) => {
                  'senseIndex': ex.senseIndex,
                  'senseText': ex.senseText,
                  'textPlain': ex.textPlain,
                  'textHtml': ex.textHtml,
                  'textTranslation': ex.textTranslation,
                  'grammarNote': ex.grammarNote,
                  'sourceModel': ex.sourceModel,
                  'createdAt': ex.createdAt.toIso8601String(),
                })
            .toList();
      }
      return map;
    }));
    wordbookMap['units'] = units.map((u) => u.toMap()).toList();

    return {
      'version': currentVersion,
      'createdAt': DateTime.now().toIso8601String(),
      'wordbooks': [wordbookMap],
    };
  }

  /// 导出所有词书为JSON格式
  Future<Map<String, dynamic>> exportAllWordbooks() async {
    final allWordbooks = await _wordbookService.getAllWordbooks();
    final List<Map<String, dynamic>> exportData = [];

    for (final wordbook in allWordbooks) {
      final words = await _wordbookService.getWordbookWords(wordbook.id!);
      final units = await _unitService.getUnitsByWordbookId(wordbook.id!);
      final wordbookMap = wordbook.toMap();
      wordbookMap['words'] = await Future.wait(words.map((w) async {
        final map = w.toMap();
        if (w.id != null) {
          final examples = await _exampleService.getExamplesByWordId(w.id!);
          map['examples'] = examples
              .map((ex) => {
                    'senseIndex': ex.senseIndex,
                    'senseText': ex.senseText,
                    'textPlain': ex.textPlain,
                    'textHtml': ex.textHtml,
                    'textTranslation': ex.textTranslation,
                    'grammarNote': ex.grammarNote,
                    'sourceModel': ex.sourceModel,
                    'createdAt': ex.createdAt.toIso8601String(),
                  })
              .toList();
        }
        return map;
      }));
      wordbookMap['units'] = units.map((u) => u.toMap()).toList();
      exportData.add(wordbookMap);
    }

    return {
      'version': currentVersion,
      'dataType': 'wordbooks',
      'createdAt': DateTime.now().toIso8601String(),
      'wordbooks': exportData,
    };
  }

  /// 验证JSON数据格式是否有效
  bool validateJsonFormat(Map<String, dynamic> jsonData) {
    // 检查基本结构
    if (jsonData['wordbooks'] == null || jsonData['wordbooks'] is! List) {
      return false;
    }

    final List<dynamic> wordbooksData = jsonData['wordbooks'];
    if (wordbooksData.isEmpty) {
      return false;
    }

    // 检查每个词书的基本字段
    for (final wordbookData in wordbooksData) {
      if (wordbookData is! Map<String, dynamic>) {
        return false;
      }
      
      // 检查是否有name字段
      if (wordbookData['name'] == null) {
        return false;
      }

      // 检查words字段格式
      if (wordbookData['words'] != null && wordbookData['words'] is! List) {
        return false;
      }

      // 检查units字段格式
      if (wordbookData['units'] != null && wordbookData['units'] is! List) {
        return false;
      }
    }

    return true;
  }

  /// 从JSON数据中提取词书信息
  Map<String, dynamic> extractWordbookInfo(Map<String, dynamic> jsonData, {int index = 0}) {
    if (!validateJsonFormat(jsonData)) {
      throw Exception('无效的JSON格式');
    }

    final List<dynamic> wordbooksData = jsonData['wordbooks'];
    if (index >= wordbooksData.length) {
      throw Exception('词书索引超出范围');
    }

    final wordbookData = wordbooksData[index];
    final List<Word> words = [];
    final Map<String, List<Map<String, dynamic>>> wordExamples = {};
    
    if (wordbookData['words'] != null && wordbookData['words'] is List) {
      final List<dynamic> wordsData = wordbookData['words'];
      for (final wordData in wordsData) {
        if (wordData is Map<String, dynamic>) {
          words.add(Word.fromMap(wordData));
          // 收集例句（按 prompt 关联）
          final examples = wordData['examples'];
          if (examples is List) {
            wordExamples[wordData['prompt'] ?? ''] = examples
                .whereType<Map<String, dynamic>>()
                .map((e) => {
                      'senseIndex': e['senseIndex'] ?? 0,
                      'senseText': e['senseText'] ?? '',
                      'textPlain': e['textPlain'] ?? '',
                      'textHtml': e['textHtml'] ?? '',
                      'textTranslation': e['textTranslation'] ?? '',
                      'grammarNote': e['grammarNote'] ?? '',
                      'sourceModel': e['sourceModel'],
                    })
                .toList();
          }
        }
      }
    }

    // 提取单元信息
    final List<Map<String, dynamic>> units = [];
    if (wordbookData['units'] != null && wordbookData['units'] is List) {
      final List<dynamic> unitsData = wordbookData['units'];
      for (final unitData in unitsData) {
        units.add(Map<String, dynamic>.from(unitData));
      }
    }

    return {
      'name': wordbookData['name'] ?? '导入的词书',
      'description': wordbookData['description'],
      'words': words,
      'units': units,
      'version': jsonData['version'],
      'createdAt': jsonData['createdAt'],
      'wordExamples': wordExamples,
    };
  }

  /// 从JSON数据中提取所有词书信息
  List<Map<String, dynamic>> extractAllWordbooksInfo(Map<String, dynamic> jsonData) {
    if (!validateJsonFormat(jsonData)) {
      throw Exception('无效的JSON格式');
    }

    final List<dynamic> wordbooksData = jsonData['wordbooks'];
    final List<Map<String, dynamic>> result = [];

    for (int i = 0; i < wordbooksData.length; i++) {
      result.add(extractWordbookInfo(jsonData, index: i));
    }

    return result;
  }

  /// 导入词书数据
  Future<void> importWordbooks(Map<String, dynamic> jsonData) async {
    final wordbooksInfo = extractAllWordbooksInfo(jsonData);
    
    for (final wordbookInfo in wordbooksInfo) {
      await _wordbookService.importAndUpdateWordbook(
        name: wordbookInfo['name'],
        words: wordbookInfo['words'],
        wordExamples: (wordbookInfo['wordExamples'] as Map<String, List<Map<String, dynamic>>>?),
        units: wordbookInfo['units'],
        description: wordbookInfo['description'],
        originalFileName: 'import-${DateTime.now().millisecondsSinceEpoch}.json',
      );
    }
  }

  /// 将JSON数据转换为字符串
  String toJsonString(Map<String, dynamic> jsonData) {
    return jsonEncode(jsonData);
  }

  /// 从字符串解析JSON数据
  Map<String, dynamic> fromJsonString(String jsonString) {
    try {
      final jsonData = jsonDecode(jsonString);
      if (jsonData is! Map<String, dynamic>) {
        throw Exception('JSON格式错误：根对象必须是Map');
      }
      return jsonData;
    } catch (e) {
      throw Exception('JSON解析失败: $e');
    }
  }
}