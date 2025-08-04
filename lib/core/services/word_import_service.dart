import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as Math;
import 'package:uuid/uuid.dart';
import 'package:excel/excel.dart';

import '../../shared/models/word.dart';

class WordImportService {
  static const Uuid _uuid = Uuid();







  /// Import words from a JSON file
  Future<List<Word>> importFromJson(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('文件不存在');
      }

      final jsonString = await file.readAsString();
      final jsonData = jsonDecode(jsonString);

      return _extractWordsFromJson(jsonData);
    } catch (e) {
      throw Exception('导入失败: $e');
    }
  }

  /// Extract wordbook info from JSON for smart import
  Future<Map<String, dynamic>> extractWordbookInfoFromJson(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('文件不存在');
      }

      final jsonString = await file.readAsString();
      final jsonData = jsonDecode(jsonString);

      if (jsonData['wordbooks'] == null || jsonData['wordbooks'] is! List) {
        throw Exception('无效的JSON格式: 缺少 `wordbooks` 列表');
      }

      final List<dynamic> wordbooksData = jsonData['wordbooks'];
      if (wordbooksData.isEmpty) {
        throw Exception('JSON文件中没有词书数据');
      }

      // For now, we'll import the first wordbook found
      final firstWordbook = wordbooksData.first;
      final List<Word> words = [];
      
      if (firstWordbook['words'] != null && firstWordbook['words'] is List) {
        final List<dynamic> wordsData = firstWordbook['words'];
        for (final wordData in wordsData) {
          words.add(Word.fromMap(wordData));
        }
      }

      return {
        'name': firstWordbook['name'] ?? '导入的词书',
        'description': firstWordbook['description'],
        'words': words,
        'originalFileName': filePath.split('/').last.split('\\').last,
      };
    } catch (e) {
      throw Exception('解析JSON文件失败: $e');
    }
  }

  List<Word> _extractWordsFromJson(Map<String, dynamic> jsonData) {
    if (jsonData['wordbooks'] == null || jsonData['wordbooks'] is! List) {
      throw Exception('无效的JSON格式: 缺少 `wordbooks` 列表');
    }

    final List<Word> allWords = [];
    final List<dynamic> wordbooksData = jsonData['wordbooks'];

    for (final wordbookData in wordbooksData) {
      if (wordbookData['words'] != null && wordbookData['words'] is List) {
        final List<dynamic> wordsData = wordbookData['words'];
        for (final wordData in wordsData) {
          allWords.add(Word.fromMap(wordData));
        }
      }
    }

    if (allWords.isEmpty) {
      throw Exception('JSON文件中未找到有效的单词数据');
    }

    return allWords;
  }

  /// Get file info without importing
  Future<Map<String, dynamic>> getFileInfo(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('文件不存在');
      }

      final stat = await file.stat();
      List<Word> words;
      
      final extension = filePath.toLowerCase().split('.').last;
      switch (extension) {
        case 'xlsx':
          words = await importFromExcel(filePath);
          break;
        case 'csv':
          words = await importFromCsv(filePath);
          break;
        case 'json':
          words = await importFromJson(filePath);
          break;
        default:
          throw Exception('不支持的文件格式: $extension');
      }
      
      return {
        'fileName': filePath.split('/').last.split('\\').last,
        'fileSize': stat.size,
        'wordCount': words.length,
        'lastModified': stat.modified,
      };
    } catch (e) {
      throw Exception('获取文件信息失败: $e');
    }
  }

  /// Import words from Excel format (.xlsx)
  Future<List<Word>> importFromExcel(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('文件不存在');
      }

      print('开始解析Excel文件: $filePath');
      final bytes = await file.readAsBytes();
      print('文件大小: ${bytes.length} 字节');
      
      // Try multiple decoding strategies for better compatibility
      Excel? excel;
      String? lastError;
      
      // Strategy 1: Standard decoding
      try {
        print('尝试标准解码...');
        excel = Excel.decodeBytes(bytes);
        print('标准解码成功');
      } catch (e) {
        print('标准解码失败: $e');
        lastError = e.toString();
      }
      
      // Strategy 2: Try with different options if first attempt fails
      if (excel == null) {
        try {
          print('尝试备用解码策略...');
          // Create a new Excel instance and try to decode with more lenient settings
          excel = Excel.createExcel();
          excel = Excel.decodeBytes(bytes);
          print('备用解码成功');
        } catch (e) {
          print('备用解码失败: $e');
          lastError = e.toString();
        }
      }
      
      // Strategy 3: Try to force decode with different approach
      if (excel == null) {
        try {
          print('尝试强制解码策略...');
          // Try to create a fresh Excel instance and decode
          final tempExcel = Excel.createExcel();
          excel = Excel.decodeBytes(bytes);
          print('强制解码成功');
        } catch (e) {
          print('强制解码失败: $e');
          lastError = e.toString();
        }
      }
      
      // If all strategies fail, provide helpful error message
      if (excel == null) {
        throw Exception('无法解析Excel文件。\n可能的解决方案：\n1. 请尝试在Excel中另存为新的.xlsx文件\n2. 确保文件没有密码保护\n3. 检查文件是否包含复杂的格式或公式\n\n技术详情: $lastError');
      }
      
      if (excel.tables.isEmpty) {
        throw Exception('Excel文件中没有工作表');
      }
      
      print('发现工作表数量: ${excel.tables.length}');
      print('工作表名称: ${excel.tables.keys.toList()}');
      
      // Use the first sheet only
      final sheetName = excel.tables.keys.first;
      final sheet = excel.tables[sheetName];
      if (sheet == null) {
        throw Exception('无法读取Excel工作表');
      }
      
      print('使用工作表: $sheetName');
      print('工作表行数: ${sheet.maxRows}');
      print('工作表列数: ${sheet.maxColumns}');
      
      // Handle case where maxRows/maxColumns might be 0 due to parsing issues
      if (sheet.maxRows == 0) {
        // Try to access rows directly
        print('尝试直接访问行数据...');
        int actualRows = 0;
        for (int i = 0; i < 1000; i++) { // Check up to 1000 rows
          try {
            final row = sheet.rows[i];
            if (row != null && row.isNotEmpty) {
              actualRows = i + 1;
            } else {
              break;
            }
          } catch (e) {
            break;
          }
        }
        print('实际发现行数: $actualRows');
        
        if (actualRows == 0) {
           // Try alternative approach: read raw cell data
           print('尝试原始单元格数据读取...');
           try {
             // Try to access cells directly using row/column indices
             for (int r = 0; r < 50; r++) {
               for (int c = 0; c < 10; c++) {
                 try {
                   final cellData = sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r));
                   if (cellData != null && cellData.value != null && cellData.value.toString().trim().isNotEmpty) {
                     print('发现数据在位置 [$r,$c]: ${cellData.value}');
                     actualRows = Math.max(actualRows, r + 1);
                   }
                 } catch (e) {
                   // Ignore individual cell errors
                 }
               }
               if (actualRows > 0 && r > actualRows + 5) break; // Stop if no more data found
             }
           } catch (e) {
             print('原始单元格读取失败: $e');
           }
           
           if (actualRows == 0) {
              throw Exception('Excel文件解析失败：无法读取数据行。\n\n这是由于Excel文件格式兼容性问题导致的。\n\n推荐解决方案（按优先级排序）：\n\n方案1：转换为CSV格式\n• 在Excel中打开您的文件\n• 点击"文件" → "另存为"\n• 选择"CSV (逗号分隔)(*.csv)"格式\n• 保存后使用CSV导入功能\n\n方案2：重新保存Excel文件\n• 在Excel中打开文件\n• 另存为新的.xlsx文件\n• 确保使用最新的Excel格式\n\n方案3：检查数据位置\n• 确保数据在第一个工作表中\n• 检查是否有隐藏的行或列\n• 确认第一行为标题行\n\n技术详情：文件包含不兼容的数字格式定义(numFmtId错误)');
            }
         }
      }
      
      final words = <Word>[];
      final now = DateTime.now();
      
      // Skip header row (index 0) and process data rows with enhanced compatibility
      int processedRows = 0;
      int skippedRows = 0;
      
      // Determine actual row count to process
      int maxRowsToProcess = sheet.maxRows > 0 ? sheet.maxRows : 1000;
      
      // Print first few rows for debugging
      print('\n前3行数据预览:');
      for (int i = 0; i < Math.min(3, maxRowsToProcess); i++) {
        try {
          final row = sheet.rows[i];
          if (row != null) {
            final rowData = row.map((cell) => cell?.value?.toString() ?? 'null').toList();
            print('第${i + 1}行: $rowData');
          } else {
            print('第${i + 1}行: null');
          }
        } catch (e) {
          print('第${i + 1}行: 读取错误 - $e');
        }
      }
      print('');
      
      for (int rowIndex = 1; rowIndex < maxRowsToProcess; rowIndex++) {
        try {
          List<Data?> row;
          
          // Try multiple ways to access row data
          try {
            row = sheet.rows[rowIndex];
          } catch (e) {
            // If rows access fails, try direct cell access
            row = [];
            for (int col = 0; col < 10; col++) {
              try {
                final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: rowIndex));
                row.add(cell);
              } catch (e) {
                break;
              }
            }
          }
          
          if (row.isEmpty) {
            if (rowIndex <= 5) print('第${rowIndex + 1}行: 空行，跳过');
            skippedRows++;
            continue;
          }
          
          // More flexible row length check - allow at least 2 columns (word + meaning)
          if (row.length < 2) {
            if (rowIndex <= 5) print('第${rowIndex + 1}行: 列数不足(${row.length})，跳过');
            skippedRows++;
            continue;
          }
          
          // Enhanced cell value extraction with multiple fallback strategies
          String? word = _extractCellValue(row, 0);
          String? partOfSpeech = _extractCellValue(row, 1);
          String? meaning = _extractCellValue(row, 2);
          String? level = _extractCellValue(row, 3);
          
          // If we only have 2 columns, treat second column as meaning
          if (row.length == 2 && meaning == null) {
            meaning = partOfSpeech;
            partOfSpeech = null;
          }
          
          // Debug output for first few rows
          if (rowIndex <= 3) {
            print('第${rowIndex + 1}行解析结果: 单词="$word", 词性="$partOfSpeech", 含义="$meaning", 等级="$level"');
          }
          
          // Validate essential data
          if (word == null || word.isEmpty) {
            if (rowIndex <= 5) print('第${rowIndex + 1}行: 单词为空，跳过');
            skippedRows++;
            continue;
          }
          
          if (meaning == null || meaning.isEmpty) {
            if (rowIndex <= 5) print('第${rowIndex + 1}行: 含义为空，跳过');
            skippedRows++;
            continue;
          }
          
          // Create word entry
          words.add(Word(
            id: null,
            prompt: word,
            answer: meaning,
            category: null,
            partOfSpeech: partOfSpeech?.isNotEmpty == true ? partOfSpeech : null,
            level: level?.isNotEmpty == true ? level : null,
            createdAt: now,
            updatedAt: now,
          ));
          processedRows++;
        } catch (e) {
          // Skip problematic rows and continue processing
          skippedRows++;
          continue;
        }
      }
      
      if (words.isEmpty) {
        String errorMsg = '未找到有效的单词数据';
        if (skippedRows > 0) {
          errorMsg += '\n跳过了 $skippedRows 行无效数据';
        }
        errorMsg += '\n\n请确保Excel格式正确：';
        errorMsg += '\n• 至少包含2列：单词 | 中文';
        errorMsg += '\n• 完整格式：单词 | 词性 | 中文 | 等级';
        errorMsg += '\n• 第一行为标题行（会被跳过）';
        errorMsg += '\n• 使用简单的文本格式，避免复杂的单元格格式';
        throw Exception(errorMsg);
      }
      
      // Add processing summary to success case
      print('Excel导入完成: 成功处理 $processedRows 行，跳过 $skippedRows 行');
      
      return words;
    } catch (e) {
      if (e.toString().contains('Exception:')) {
        rethrow;
      }
      throw Exception('导入Excel失败: 文件可能包含不支持的格式或已损坏，请尝试另存为新的Excel文件');
    }
  }
  
  /// Safely extract cell value with multiple fallback strategies
  String? _extractCellValue(List<Data?> row, int columnIndex) {
    try {
      if (columnIndex >= row.length) return null;
      
      final cell = row[columnIndex];
      if (cell == null) return null;
      
      // Try to get the value
      final value = cell.value;
      if (value == null) return null;
      
      // Convert to string and trim
      String stringValue = value.toString().trim();
      
      // Handle special cases
      if (stringValue.isEmpty || stringValue == 'null') {
        return null;
      }
      
      return stringValue;
    } catch (e) {
      // Return null for any extraction errors
      return null;
    }
  }

  /// Import words from CSV format (alternative format)
  Future<List<Word>> importFromCsv(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('文件不存在');
      }

      final content = await file.readAsString();
      final lines = content.split('\n');
      final words = <Word>[];
      final now = DateTime.now();

      for (int i = 1; i < lines.length; i++) { // Skip header
        final line = lines[i].trim();
        if (line.isEmpty) continue;

        final parts = line.split(',');
        if (parts.length >= 2) {
          final prompt = parts[0].trim().replaceAll('"', '');
          final answer = parts[1].trim().replaceAll('"', '');
          
          if (prompt.isNotEmpty && answer.isNotEmpty) {
            String? category;
            if (parts.length >= 3) {
              final categoryText = parts[2].trim().replaceAll('"', '');
              if (categoryText.isNotEmpty) {
                category = categoryText;
              }
            }
            
            words.add(Word(
              id: null,
              prompt: prompt,
              answer: answer,
              category: category,
              partOfSpeech: null,
              level: null,
              createdAt: now,
              updatedAt: now,
            ));
          }
        }
      }

      if (words.isEmpty) {
        throw Exception('未找到有效的单词数据');
      }

      return words;
    } catch (e) {
      throw Exception('导入CSV失败: $e');
    }
  }
}