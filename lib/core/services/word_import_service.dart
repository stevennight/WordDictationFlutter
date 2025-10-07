import 'dart:convert';
import 'dart:io';
import 'dart:math' as Math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:path/path.dart' as path;

import 'package:flutter_word_dictation/shared/models/word.dart';
import 'import_data_service.dart';
import 'json_data_service.dart';

class WordImportService {
  /// WPS compatibility preprocessing for Excel bytes
  Uint8List _preprocessWpsBytes(Uint8List bytes) {
    try {
      // First, let's examine the actual content to understand the format
      String content = utf8.decode(bytes, allowMalformed: true);
      print('开始WPS预处理，原始内容长度: ${content.length}');
      
      // Debug: Check if this is actually an Excel file or ZIP archive
      if (content.startsWith('PK')) {
        print('检测到ZIP格式的Excel文件，需要解压处理');
        // This is a ZIP-based Excel file, we need different handling
        return _preprocessZipBasedExcel(bytes);
      }
      
      // For XML-based content, continue with existing logic
      int replacements = 0;

      // Strategy 1: More comprehensive numFmtId pattern matching
       content = content.replaceAllMapped(
         RegExp(r'numFmtId\s*=\s*["\x27]41["\x27]'),
         (match) {
           replacements++;
           return 'numFmtId="0"'; // Use General format
         },
       );
      print('替换了 $replacements 个 numFmtId="41" 实例');
      
      // Strategy 2: Remove entire numFmt elements with problematic IDs
       content = content.replaceAll(
         RegExp(r'<numFmt[^>]*numFmtId\s*=\s*["\x27]41["\x27][^>]*/?>', dotAll: true),
         '',
       );
      
      // Strategy 3: Handle other problematic numFmtId values
       content = content.replaceAllMapped(
         RegExp(r'numFmtId\s*=\s*["\x27]([0-9]+)["\x27]'),
         (match) {
           int id = int.tryParse(match.group(1) ?? '0') ?? 0;
           if (id == 41 || (id > 0 && id < 164 && id != 14 && id != 22)) {
             // Replace problematic IDs
             return 'numFmtId="0"';
           }
           return match.group(0) ?? '';
         },
       );
      
      // Strategy 4: Completely remove numFmts section if it exists
      content = content.replaceAll(
        RegExp(r'<numFmts[^>]*>.*?</numFmts>', dotAll: true),
        '',
      );
      
      print('WPS预处理完成，处理后内容长度: ${content.length}');
      return Uint8List.fromList(utf8.encode(content));
    } catch (e) {
      print('WPS预处理异常: $e');
      return bytes; // Return original bytes if preprocessing fails
    }
  }
  
  /// Handle ZIP-based Excel files (XLSX format)
  Uint8List _preprocessZipBasedExcel(Uint8List bytes) {
    try {
      // Decode the ZIP archive
      final archive = ZipDecoder().decodeBytes(bytes);
      
      // Find and modify xl/styles.xml
      List<ArchiveFile> modifiedFiles = [];
      bool stylesModified = false;
      
      for (final file in archive.files) {
        if (file.name == 'xl/styles.xml' && file.isFile) {
          // Get the content of styles.xml
          final content = utf8.decode(file.content as List<int>);
          
          // Apply WPS compatibility fixes to styles.xml
          String modifiedContent = _fixStylesXmlContent(content);
          
          if (modifiedContent != content) {
             // Create a new ArchiveFile with modified content
             final newContent = utf8.encode(modifiedContent);
             final newFile = ArchiveFile(file.name, newContent.length, newContent);
             modifiedFiles.add(newFile);
             stylesModified = true;
           } else {
             modifiedFiles.add(file);
           }
        } else {
          modifiedFiles.add(file);
        }
      }
      
      if (stylesModified) {
        // Create a new archive with modified files
        final newArchive = Archive();
        for (final file in modifiedFiles) {
          newArchive.addFile(file);
        }
        
        // Repackage the ZIP
        final encoder = ZipEncoder();
        final newZipBytes = encoder.encode(newArchive);
        return Uint8List.fromList(newZipBytes ?? bytes);
      } else {
        return bytes;
      }
    } catch (e) {
      print('ZIP预处理失败: $e');
      return bytes;
    }
  }
  
  /// Fix numFmtId issues in styles.xml content
  String _fixStylesXmlContent(String content) {
    try {
      String modifiedContent = content;
      
      // Strategy 1: Simply remove the entire numFmts section if it exists
      if (content.contains('<numFmts')) {
        modifiedContent = modifiedContent.replaceAll(
          RegExp(r'<numFmts[^>]*>.*?</numFmts>', dotAll: true),
          '',
        );
      }
      
      // Strategy 2: Replace any remaining numFmtId references with default (General format)
      modifiedContent = modifiedContent.replaceAllMapped(
        RegExp(r'numFmtId\s*=\s*["\x27]([0-9]+)["\x27]'),
        (match) {
          int id = int.tryParse(match.group(1) ?? '0') ?? 0;
          // Only allow built-in format IDs (0-22)
          if (id > 22) {
            return 'numFmtId="0"'; // General format
          }
          return match.group(0) ?? '';
        },
      );
      
      return modifiedContent;
    } catch (e) {
      print('修复styles.xml时出错: $e');
      return content; // Return original content if fixing fails
    }
  }
  
  /// Enhanced WPS-compatible Excel decoding
  Excel? _decodeWithWpsCompatibility(Uint8List bytes) {
    try {
      // Strategy: Try multiple Excel creation approaches for WPS files
      
      // Approach 1: Try with preprocessed bytes first (most likely to work)
      try {
        final processedBytes = _preprocessWpsBytes(bytes);
        final excel = Excel.decodeBytes(processedBytes);
        return excel;
      } catch (e) {
        // Continue to next approach
      }
      
      // Approach 2: Standard decode with error catching
      try {
        return Excel.decodeBytes(bytes);
      } catch (e) {
        // Continue to next approach
      }
      
      // Approach 3: Try creating empty Excel and decoding (last resort)
      try {
        final excel = Excel.createExcel();
        // Clear any existing sheets
        excel.tables.clear();
        // Try to decode the original bytes
        return Excel.decodeBytes(bytes);
      } catch (e) {
        // Final fallback failed
      }
      
      return null;
    } catch (e) {
      return null;
    }
  }







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
    final importDataService = ImportDataService();
    return await importDataService.extractWordbookInfoFromFile(filePath);
  }

  List<Word> _extractWordsFromJson(Map<String, dynamic> jsonData) {
    final jsonDataService = JsonDataService();
    final wordbooksInfo = jsonDataService.extractAllWordbooksInfo(jsonData);
    
    final List<Word> allWords = [];
    for (final wordbookInfo in wordbooksInfo) {
      allWords.addAll(wordbookInfo['words'] as List<Word>);
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
        'fileName': path.basename(filePath),
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

      final bytes = await file.readAsBytes();
      
      // Try multiple decoding strategies for better compatibility
      Excel? excel;
      String? lastError;
      
      // Strategy 1: Standard decoding
      try {
        excel = Excel.decodeBytes(bytes);
      } catch (e) {
        lastError = e.toString();
      }
      
      // Strategy 2: WPS compatibility mode - try to handle numFmtId issues
      if (excel == null && lastError != null && (lastError.contains('custom numFmtId') || lastError.contains('numFmtId'))) {
        try {
          excel = _decodeWithWpsCompatibility(bytes);
        } catch (e) {
          lastError = e.toString();
        }
      }
      
      // Strategy 3: Try with different options if first attempts fail
      if (excel == null) {
        try {
          // Create a new Excel instance and try to decode with more lenient settings
          excel = Excel.createExcel();
          excel = Excel.decodeBytes(bytes);
        } catch (e) {
          lastError = e.toString();
        }
      }
      
      // Strategy 4: Try to force decode with different approach
      if (excel == null) {
        try {
          // Try to create a fresh Excel instance and decode
          excel = Excel.decodeBytes(bytes);
        } catch (e) {
          lastError = e.toString();
        }
      }
      
      // If all strategies fail, provide helpful error message with WPS-specific guidance
      if (excel == null) {
        String errorMessage = '无法解析Excel文件。';
        
        if (lastError != null && (lastError.contains('custom numFmtId') || lastError.contains('numFmtId'))) {
          errorMessage += '\n\n检测到WPS Office兼容性问题：\n';
          errorMessage += '• WPS生成的Excel文件使用了非标准的数字格式定义\n';
          errorMessage += '• 这会导致标准Excel解析库无法正确读取文件\n\n';
          errorMessage += 'WPS文件解决方案（推荐按顺序尝试）：\n\n';
          errorMessage += '方案1：在WPS中重新保存\n';
          errorMessage += '• 在WPS中打开文件\n';
          errorMessage += '• 选择"文件" → "另存为"\n';
          errorMessage += '• 格式选择"Excel工作簿(.xlsx)"\n';
          errorMessage += '• 确保兼容性设置为"Excel 2016"或更高版本\n\n';
          errorMessage += '方案2：转换为CSV格式\n';
          errorMessage += '• 在WPS中选择"文件" → "另存为"\n';
          errorMessage += '• 格式选择"CSV (逗号分隔)(*.csv)"\n';
          errorMessage += '• 使用本应用的CSV导入功能\n\n';
          errorMessage += '方案3：使用Microsoft Excel\n';
          errorMessage += '• 在Microsoft Excel中打开文件\n';
          errorMessage += '• 另存为新的.xlsx文件\n';
        } else {
          errorMessage += '\n可能的解决方案：\n1. 请尝试在Excel中另存为新的.xlsx文件\n2. 确保文件没有密码保护\n3. 检查文件是否包含复杂的格式或公式';
        }
        
        errorMessage += '\n\n技术详情: $lastError';
        throw Exception(errorMessage);
      }
      
      if (excel.tables.isEmpty) {
        throw Exception('Excel文件中没有工作表');
      }
      
      // Use the first sheet only
      final sheetName = excel.tables.keys.first;
      final sheet = excel.tables[sheetName];
      if (sheet == null) {
        throw Exception('无法读取Excel工作表');
      }
      
      // Handle case where maxRows/maxColumns might be 0 due to parsing issues
      if (sheet.maxRows == 0) {
        // Try to access rows directly
        int actualRows = 0;
        for (int i = 0; i < 1000; i++) { // Check up to 1000 rows
          try {
            final row = sheet.rows[i];
            if (row.isNotEmpty) {
              actualRows = i + 1;
            } else {
              break;
            }
          } catch (e) {
            break;
          }
        }
        
        if (actualRows == 0) {
           // Try alternative approach: read raw cell data
           try {
             // Try to access cells directly using row/column indices
             for (int r = 0; r < 50; r++) {
               for (int c = 0; c < 10; c++) {
                 try {
                   final cellData = sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r));
                   if (cellData.value != null && cellData.value.toString().trim().isNotEmpty) {
                     actualRows = Math.max(actualRows, r + 1);
                   }
                 } catch (e) {
                   // Ignore individual cell errors
                 }
               }
               if (actualRows > 0 && r > actualRows + 5) break; // Stop if no more data found
             }
           } catch (e) {
             // Ignore raw cell reading errors
           }
           
           if (actualRows == 0) {
              throw Exception('Excel文件解析失败：无法读取数据行。\n\n这是由于Excel文件格式兼容性问题导致的。\n\n推荐解决方案（按优先级排序）：\n\n方案1：转换为CSV格式\n• 在Excel中打开您的文件\n• 点击"文件" → "另存为"\n• 选择"CSV (逗号分隔)(*.csv)"格式\n• 保存后使用CSV导入功能\n\n方案2：重新保存Excel文件\n• 在Excel中打开文件\n• 另存为新的.xlsx文件\n• 确保使用最新的Excel格式\n\n方案3：检查数据位置\n• 确保数据在第一个工作表中\n• 检查是否有隐藏的行或列\n• 确认第一行为标题行\n\n技术详情：文件包含不兼容的数字格式定义(numFmtId错误)');
            }
         }
      }
      
      final words = <Word>[];
      final now = DateTime.now();
      
      // Skip header row (index 0) and process data rows with enhanced compatibility
      int skippedRows = 0;
      
      // Determine actual row count to process
      int maxRowsToProcess = sheet.maxRows > 0 ? sheet.maxRows : 1000;
      
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
            skippedRows++;
            continue;
          }
          
          // More flexible row length check - allow at least 2 columns (word + meaning)
          if (row.length < 2) {
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
          
          // Validate essential data
          if (word == null || word.isEmpty) {
            skippedRows++;
            continue;
          }
          
          if (meaning == null || meaning.isEmpty) {
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