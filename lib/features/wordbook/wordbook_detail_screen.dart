import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../../shared/models/word.dart';
import '../../shared/models/wordbook.dart';
import '../../shared/models/unit.dart';
import '../../shared/models/dictation_session.dart';
import '../../shared/providers/dictation_provider.dart';
import '../../shared/widgets/unified_dictation_config_dialog.dart';
import '../../core/services/wordbook_service.dart';
import '../../core/services/unit_service.dart';
import '../../core/database/database_helper.dart';
import 'wordbook_import_screen.dart';
import '../dictation/screens/dictation_screen.dart';
import '../dictation/screens/copying_screen.dart';
import 'widgets/wordbook_quantity_selection_dialog.dart';
import 'widgets/dictation_mode_selection_dialog.dart';

enum UnitSortType {
  nameAsc,
  nameDesc,
  wordCountAsc,
  wordCountDesc,
  createdTimeAsc,
  createdTimeDesc,
}

enum UnitLearningFilter {
  all,
  learned,
  unlearned,
}

class WordbookDetailScreen extends StatefulWidget {
  final Wordbook wordbook;

  const WordbookDetailScreen({super.key, required this.wordbook});

  @override
  State<WordbookDetailScreen> createState() => _WordbookDetailScreenState();
}

class _WordbookDetailScreenState extends State<WordbookDetailScreen> {
  final WordbookService _wordbookService = WordbookService();
  final UnitService _unitService = UnitService();
  List<Word> _words = [];
  List<Word> _filteredWords = [];
  List<Unit> _units = [];
  List<Unit> _filteredUnits = [];
  Map<String, List<Word>> _unitWords = {};
  bool _isLoading = true;
  String _searchQuery = '';
  bool _isWordView = false; // true for word view, false for unit view
  String? _selectedUnit; // 选中的单元，null表示显示所有单元
  UnitSortType _unitSortType = UnitSortType.nameAsc;
  UnitLearningFilter _unitLearningFilter = UnitLearningFilter.all;
  int _currentWordCount = 0; // 当前实际的单词数量

  @override
  void initState() {
    super.initState();
    _loadWords();
    _updateWordbookWordCount();
  }
  
  Future<void> _updateWordbookWordCount() async {
    try {
      await _wordbookService.updateWordbookWordCount(widget.wordbook.id!);
    } catch (e) {
      // 静默处理错误，不影响页面加载
    }
  }

  void _organizeWordsByUnit() {
    _unitWords.clear();
    
    // 为每个单元创建单词列表
    for (final unit in _units) {
      _unitWords[unit.name] = [];
    }
    
    // 将单词分配到对应的单元
    for (final word in _words) {
      if (word.unitId != null) {
        final unit = _units.firstWhere(
          (u) => u.id == word.unitId,
          orElse: () => Unit(
            id: -1,
            name: '未分类',
            wordbookId: widget.wordbook.id!,
            wordCount: 0,
            isLearned: false,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );
        
        if (!_unitWords.containsKey(unit.name)) {
          _unitWords[unit.name] = [];
        }
        _unitWords[unit.name]!.add(word);
      } else {
        // 处理没有单元ID的单词
        if (!_unitWords.containsKey('未分类')) {
          _unitWords['未分类'] = [];
        }
        _unitWords['未分类']!.add(word);
      }
    }
    
    // 保留所有单元，包括空单元
    // _unitWords.removeWhere((key, value) => value.isEmpty);
  }

  void _filterUnits() {
    List<Unit> unitsToFilter = _units;
    
    // 按学习状态过滤
    switch (_unitLearningFilter) {
      case UnitLearningFilter.learned:
        unitsToFilter = _units.where((unit) => unit.isLearned).toList();
        break;
      case UnitLearningFilter.unlearned:
        unitsToFilter = _units.where((unit) => !unit.isLearned).toList();
        break;
      case UnitLearningFilter.all:
      default:
        unitsToFilter = _units;
        break;
    }
    
    // 按搜索查询过滤
    if (_searchQuery.isNotEmpty) {
      unitsToFilter = unitsToFilter
          .where((unit) => unit.name.toLowerCase().contains(_searchQuery.toLowerCase()))
          .toList();
    }
    
    // 排序
    switch (_unitSortType) {
      case UnitSortType.nameAsc:
        unitsToFilter.sort((a, b) => a.name.compareTo(b.name));
        break;
      case UnitSortType.nameDesc:
        unitsToFilter.sort((a, b) => b.name.compareTo(a.name));
        break;
      case UnitSortType.wordCountAsc:
        unitsToFilter.sort((a, b) => (_unitWords[a.name]?.length ?? 0).compareTo(_unitWords[b.name]?.length ?? 0));
        break;
      case UnitSortType.wordCountDesc:
        unitsToFilter.sort((a, b) => (_unitWords[b.name]?.length ?? 0).compareTo(_unitWords[a.name]?.length ?? 0));
        break;
      case UnitSortType.createdTimeAsc:
        unitsToFilter.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        break;
      case UnitSortType.createdTimeDesc:
        unitsToFilter.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
    }
    
    _filteredUnits = unitsToFilter;
  }

  int _getUnlearnedWordsCount() {
    final unlearnedUnits = _units.where((unit) => !unit.isLearned);
    int count = 0;
    for (final unit in unlearnedUnits) {
      count += _unitWords[unit.name]?.length ?? 0;
    }
    return count;
  }

  int _getLearnedWordsCount() {
    final learnedUnits = _units.where((unit) => unit.isLearned);
    int count = 0;
    for (final unit in learnedUnits) {
      count += _unitWords[unit.name]?.length ?? 0;
    }
    return count;
  }

  Future<List<Word>> _getUnlearnedWords() async {
    try {
      return await _wordbookService.getWordbookUnlearnedWords(widget.wordbook.id!);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('获取未学习单词失败: $e')),
        );
      }
      return [];
    }
  }

  Future<List<Word>> _getLearnedWords() async {
    try {
      return await _wordbookService.getWordbookLearnedWords(widget.wordbook.id!);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('获取已学习单词失败: $e')),
        );
      }
      return [];
    }
  }

  Future<void> _loadWords() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final words = await _wordbookService.getWordbookWords(widget.wordbook.id!);
      final units = await _unitService.getUnitsByWordbookId(widget.wordbook.id!);
      
      // 如果单元数量为0但有单词，尝试手动迁移数据
      if (units.isEmpty && words.isNotEmpty) {
        await _migrateDataManually();
        // 重新加载数据
        final newUnits = await _unitService.getUnitsByWordbookId(widget.wordbook.id!);
        final newWords = await _wordbookService.getWordbookWords(widget.wordbook.id!);
        setState(() {
          _words = newWords;
          _units = newUnits;
          _currentWordCount = newWords.length; // 更新当前单词数量
          _organizeWordsByUnit();
          _filterUnits();
          _applyFilters();
        });
      }
      
      setState(() {
        _words = words;
        _units = units;
        _currentWordCount = words.length; // 更新当前单词数量
        _organizeWordsByUnit();
        _filterUnits();
        _applyFilters();
        _isLoading = false;
      });
      

      
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载数据失败: $e')),
        );
      }
    }
  }

  Future<void> _exportWordbook() async {
    try {
      final jsonString = await _wordbookService.exportSingleWordbook(widget.wordbook.id!);
      
      // Let user pick a directory and file name
      final now = DateTime.now();
      final timestamp = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
      final String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: '请选择保存导出的文件',
        fileName: '${widget.wordbook.name}_export_$timestamp.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: utf8.encode(jsonString), // 添加字节数据以支持Android/iOS
      );

      if (outputFile != null) {
        final file = File(outputFile);
        await file.writeAsString(jsonString);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('词书「${widget.wordbook.name}」已成功导出到: $outputFile')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败: $e')),
        );
      }
    }
  }

  void _filterWords(String query) {
    setState(() {
      _searchQuery = query;
      if (_isWordView) {
        _applyFilters();
      } else {
        _filterUnits();
      }
    });
  }

  void _applyFilters() {
    List<Word> words = _words;
    
    // 先按单元过滤
    if (_selectedUnit != null) {
      words = words.where((word) => word.category == _selectedUnit).toList();
    }
    
    // 再按搜索查询过滤
    if (_searchQuery.isNotEmpty) {
      words = words.where((word) {
        return word.prompt.toLowerCase().contains(_searchQuery.toLowerCase()) ||
               word.answer.toLowerCase().contains(_searchQuery.toLowerCase()) ||
               (word.category?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false);
      }).toList();
    }
    
    _filteredWords = words;
  }

  Future<void> _migrateDataManually() async {
    try {
      final db = await DatabaseHelper.instance.database;
      final wordbookId = widget.wordbook.id!;
      
      // 获取该词书的所有不同类别
      final categoriesResult = await db.rawQuery('''
        SELECT DISTINCT category FROM words 
        WHERE wordbook_id = ? AND category IS NOT NULL AND category != ''
      ''', [wordbookId]);
      
      // 为每个类别创建单元
      for (final categoryMap in categoriesResult) {
        final category = categoryMap['category'] as String;
        
        // 计算该类别的单词数量
        final countResult = await db.rawQuery('''
          SELECT COUNT(*) as count FROM words 
          WHERE wordbook_id = ? AND category = ?
        ''', [wordbookId, category]);
        final wordCount = countResult.first['count'] as int;
        
        // 创建单元
        final now = DateTime.now().millisecondsSinceEpoch;
        final unitId = await db.insert('units', {
          'name': category,
          'wordbook_id': wordbookId,
          'word_count': wordCount,
          'is_learned': 0,
          'created_at': now,
          'updated_at': now,
        });
        
        // 更新该类别的所有单词，设置unit_id
        await db.update(
          'words',
          {'unit_id': unitId},
          where: 'wordbook_id = ? AND category = ?',
          whereArgs: [wordbookId, category],
        );
      }
      
      // 处理没有类别的单词（创建"未分类"单元）
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
        
        // 更新未分类单词
        await db.update(
          'words',
          {'unit_id': unitId},
          where: 'wordbook_id = ? AND (category IS NULL OR category = ?)',
          whereArgs: [wordbookId, ''],
        );
      }
    } catch (e) {
      rethrow;
    }
  }

  void _selectUnit(String? unit) {
    setState(() {
      _selectedUnit = unit;
      _applyFilters();
    });
  }

  void _startFilteredDictation(int mode, int order, List<Word> sourceWords, int count) async {
    if (sourceWords.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有可用的单词')),
      );
      return;
    }

    final wordsToUse = count >= sourceWords.length ? sourceWords : sourceWords.take(count).toList();

    try {
      final dictationProvider = Provider.of<DictationProvider>(context, listen: false);
      
      // Load words into dictation provider
      await dictationProvider.loadWordsFromWordbook(
        words: wordsToUse,
        wordbookName: widget.wordbook.name,
        mode: mode,
        order: order,
        count: wordsToUse.length,
      );

      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => const DictationScreen(),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('启动默写失败: $e')),
        );
      }
    }
  }



  Future<void> _showDictationOptions() async {
    // 显示选择对话框：整本词书还是仅未学习单元
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('选择默写范围'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.book),
              title: const Text('整本词书'),
              subtitle: Text('${_words.length} 个单词'),
              onTap: () => Navigator.of(context).pop('all'),
            ),
            ListTile(
              leading: const Icon(Icons.school),
              title: const Text('仅已学习单元'),
              subtitle: Text('${_getLearnedWordsCount()} 个单词'),
              onTap: () => Navigator.of(context).pop('learned'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
        ],
      ),
    );

    if (choice == null) return;

    List<Word> wordsToUse;
    String sourceName;
    
    if (choice == 'learned') {
      wordsToUse = await _getLearnedWords();
      sourceName = '${widget.wordbook.name} (已学习单元)';
    } else {
      wordsToUse = _filteredWords.isNotEmpty ? _filteredWords : _words;
      sourceName = _selectedUnit ?? widget.wordbook.name;
    }

    if (wordsToUse.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(choice == 'learned' ? '没有已学习单元的单词' : '没有可用的单词')),
      );
      return;
    }

    // Show unified dictation config dialog
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => UnifiedDictationConfigDialog(
        totalWords: wordsToUse.length,
        sourceName: sourceName,
        showQuantitySelection: true,
      ),
    );

    if (result == null) return;

    final mode = result['mode'] as int;
    final order = result['order'] as int;
    final quantity = result['quantity'] as int;

    _startFilteredDictation(mode, order, wordsToUse, quantity);
  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.wordbook.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: _exportWordbook,
            tooltip: '导出词书',
          ),
          IconButton(
            icon: Icon(_isWordView ? Icons.view_list : Icons.view_module),
            onPressed: () {
              setState(() {
                _isWordView = !_isWordView;
                _searchQuery = '';
                if (_isWordView) {
                  _filteredWords = _words;
                } else {
                  _filterUnits();
                }
              });
            },
            tooltip: _isWordView ? '切换到单元视图' : '切换到单词视图',
          ),

          if (_words.isNotEmpty && _isWordView)
            IconButton(
              icon: const Icon(Icons.play_arrow),
              onPressed: _showDictationOptions,
              tooltip: '开始默写',
            ),
        ],
      ),
      body: Column(
        children: [
          // Wordbook info
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Theme.of(context).primaryColor.withOpacity(0.1),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.wordbook.description != null && widget.wordbook.description!.isNotEmpty)
                  Text(
                    widget.wordbook.description!,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.book,
                      size: 16,
                      color: Colors.grey[600],
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${_currentWordCount} 个单词',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Icon(
                      Icons.access_time,
                      size: 16,
                      color: Colors.grey[600],
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _formatDate(widget.wordbook.createdAt),
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                if (widget.wordbook.originalFileName != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.file_present,
                        size: 16,
                        color: Colors.grey[600],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '来源: ${widget.wordbook.originalFileName}',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          
          // Search bar
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              key: ValueKey(_isWordView),
              decoration: InputDecoration(
                hintText: _isWordView ? '搜索单词...' : '搜索单元...',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
              ),
              onChanged: _filterWords,
            ),
          ),
          
          // Unit filter (only show in word view)
          if (_isWordView && _unitWords.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: DropdownButtonFormField<String?>(
                value: _selectedUnit,
                decoration: const InputDecoration(
                  labelText: '选择单元',
                  prefixIcon: Icon(Icons.filter_list),
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('全部单元'),
                  ),
                  ..._unitWords.keys.map((unitName) {
                    final wordCount = _unitWords[unitName]!.length;
                    return DropdownMenuItem<String?>(
                      value: unitName,
                      child: Text('$unitName ($wordCount个单词)'),
                    );
                  }),
                ],
                onChanged: _selectUnit,
              ),
            ),
          
          // Unit filters and sorting (only show in unit view)
          if (!_isWordView)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<UnitLearningFilter>(
                          value: _unitLearningFilter,
                          decoration: const InputDecoration(
                            labelText: '学习状态',
                            prefixIcon: Icon(Icons.filter_list),
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: UnitLearningFilter.all,
                              child: Text('全部单元'),
                            ),
                            DropdownMenuItem(
                              value: UnitLearningFilter.learned,
                              child: Text('已学习单元'),
                            ),
                            DropdownMenuItem(
                              value: UnitLearningFilter.unlearned,
                              child: Text('未学习单元'),
                            ),
                          ],
                          onChanged: (value) {
                            setState(() {
                              _unitLearningFilter = value ?? UnitLearningFilter.all;
                              _filterUnits();
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<UnitSortType>(
                          value: _unitSortType,
                          decoration: const InputDecoration(
                            labelText: '排序方式',
                            prefixIcon: Icon(Icons.sort),
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: UnitSortType.nameAsc,
                              child: Text('名称 A-Z'),
                            ),
                            DropdownMenuItem(
                              value: UnitSortType.nameDesc,
                              child: Text('名称 Z-A'),
                            ),
                            DropdownMenuItem(
                              value: UnitSortType.wordCountAsc,
                              child: Text('单词数 ↑'),
                            ),
                            DropdownMenuItem(
                              value: UnitSortType.wordCountDesc,
                              child: Text('单词数 ↓'),
                            ),
                            DropdownMenuItem(
                              value: UnitSortType.createdTimeAsc,
                              child: Text('创建时间 ↑'),
                            ),
                            DropdownMenuItem(
                              value: UnitSortType.createdTimeDesc,
                              child: Text('创建时间 ↓'),
                            ),
                          ],
                          onChanged: (value) {
                            setState(() {
                              _unitSortType = value ?? UnitSortType.nameAsc;
                              _filterUnits();
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          
          // Content list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _isWordView
                    ? _buildWordsList()
                    : _buildUnitsList(),
          ),
        ],
      ),
      floatingActionButton: _words.isNotEmpty && _isWordView
          ? FloatingActionButton.extended(
              onPressed: _showDictationOptions,
              icon: const Icon(Icons.play_arrow),
              label: const Text('开始默写'),
            )
          : null,
    );
  }

  Widget _buildWordsList() {
    return _filteredWords.isEmpty
        ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _searchQuery.isEmpty ? Icons.book_outlined : Icons.search_off,
                  size: 64,
                  color: Colors.grey[400],
                ),
                const SizedBox(height: 16),
                Text(
                  _searchQuery.isEmpty ? '词书中没有单词' : '没有找到匹配的单词',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.grey[600],
                  ),
                ),
                if (_searchQuery.isEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    '点击右上角的文件夹图标进入单元管理',
                    style: TextStyle(
                      color: Colors.grey[500],
                    ),
                  ),
                ],
              ],
            ),
          )
        : ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _filteredWords.length,
            itemBuilder: (context, index) {
              final word = _filteredWords[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.blue[100],
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(color: Colors.blue[800]),
                    ),
                  ),
                  title: Text(
                    word.prompt,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(word.answer),
                      if (word.partOfSpeech != null || word.level != null)
                        const SizedBox(height: 4),
                      if (word.partOfSpeech != null || word.level != null)
                        Row(
                          children: [
                            if (word.partOfSpeech != null)
                              Chip(
                                label: Text(
                                  word.partOfSpeech!,
                                  style: const TextStyle(fontSize: 10),
                                ),
                                backgroundColor: Colors.blue[100],
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            if (word.partOfSpeech != null && word.level != null)
                              const SizedBox(width: 4),
                            if (word.level != null)
                              Chip(
                                label: Text(
                                  word.level!,
                                  style: const TextStyle(fontSize: 10),
                                ),
                                backgroundColor: Colors.green[100],
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                          ],
                        ),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: () => _startWordCopying(word),
                        tooltip: '抄写',
                      ),
                      if (word.category != null)
                        Chip(
                          label: Text(
                            word.category!,
                            style: const TextStyle(fontSize: 12),
                          ),
                          backgroundColor: Colors.grey[200],
                        ),
                    ],
                  ),
                ),
              );
            },
          );
  }

  Widget _buildUnitsList() {
    return Column(
      children: [
        // 创建单元按钮
        if (_searchQuery.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _createNewUnit,
                icon: const Icon(Icons.file_upload),
                label: const Text('导入文件创建单元'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ),
        // 单元列表
        Expanded(
          child: _filteredUnits.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _searchQuery.isEmpty ? Icons.folder_outlined : Icons.search_off,
                        size: 64,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _searchQuery.isEmpty ? '词书中没有单元' : '没有找到匹配的单元',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey[600],
                        ),
                      ),
                      if (_searchQuery.isEmpty) ...[  
                        const SizedBox(height: 8),
                        Text(
                          '点击上方按钮创建第一个单元',
                          style: TextStyle(
                            color: Colors.grey[500],
                          ),
                        ),
                      ]
                    ]
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _filteredUnits.length,
                  itemBuilder: (context, index) {
                    final unit = _filteredUnits[index];
                    final unitWords = _unitWords[unit.name] ?? [];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                         leading: CircleAvatar(
                           backgroundColor: unit.isLearned ? Colors.green[100] : Colors.orange[100],
                           child: Icon(
                             unit.isLearned ? Icons.check_circle : Icons.folder,
                             color: unit.isLearned ? Colors.green[800] : Colors.orange[800],
                           ),
                          ),
                          title: Row(
                            children: [
                               Expanded(
                                 child: Text(
                                   unit.name,
                                   style: const TextStyle(fontWeight: FontWeight.bold),
                                 ),
                               ),
                               if (unit.isLearned)
                                 Container(
                                   padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                   decoration: BoxDecoration(
                                     color: Colors.green[100],
                                     borderRadius: BorderRadius.circular(12),
                                   ),
                                   child: Text(
                                     '已学习',
                                     style: TextStyle(
                                       fontSize: 12,
                                       color: Colors.green[800],
                                       fontWeight: FontWeight.w500,
                                     ),
                                   ),
                                 ),
                             ],
                           ),
                           subtitle: Column(
                             crossAxisAlignment: CrossAxisAlignment.start,
                             children: [
                                Text('${unitWords.length} 个单词'),
                                if (unit.description != null && unit.description!.isNotEmpty)
                                  Text(
                                    unit.description!,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                              ],
                            ),
                           trailing: PopupMenuButton<String>(
                             onSelected: (value) => _handleUnitAction(value, unit, unitWords),
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'view',
                                  child: ListTile(
                                    leading: Icon(Icons.visibility),
                                    title: Text('查看单词'),
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'dictation',
                                  child: ListTile(
                                    leading: Icon(Icons.play_arrow),
                                    title: Text('开始默写'),
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'copy',
                                  child: ListTile(
                                    leading: Icon(Icons.edit),
                                    title: Text('抄写练习'),
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                                const PopupMenuDivider(),

                                 PopupMenuItem(
                                   value: 'toggle_learned',
                                   child: ListTile(
                                     leading: Icon(unit.isLearned ? Icons.school_outlined : Icons.check_circle),
                                     title: Text(unit.isLearned ? '标记为未学习' : '标记为已学习'),
                                     contentPadding: EdgeInsets.zero,
                                   ),
                                 ),
                                 const PopupMenuItem(
                                   value: 'delete',
                                   child: ListTile(
                                     leading: Icon(Icons.delete, color: Colors.red),
                                     title: Text('删除单元', style: TextStyle(color: Colors.red)),
                                     contentPadding: EdgeInsets.zero,
                                   ),
                                 ),
                               ],
                             ),
                             onTap: () => _showUnitWords(unit.name, unitWords),
                           ),
                         );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _loadUnits() async {
    try {
      final units = await _unitService.getUnitsByWordbookId(widget.wordbook.id!);
      setState(() {
        _units = units;
        _filterUnits();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载单元失败: $e')),
        );
      }
    }
  }

  Future<void> _createNewUnit() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => WordbookImportScreen(
          wordbook: widget.wordbook,
          isUnitMode: true,
        ),
      ),
    );
    
    if (result == true) {
      await _loadWords();
      await _loadUnits(); // 刷新单元列表
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('单元已创建')),
        );
      }
    }
  }



  void _handleUnitAction(String action, Unit unit, List<Word> unitWords) {
    switch (action) {
      case 'view':
        _showUnitWords(unit.name, unitWords);
        break;
      case 'dictation':
        _startUnitDictation(unit.name, unitWords);
        break;
      case 'copy':
        _startUnitCopying(unit.name, unitWords);
        break;

      case 'toggle_learned':
        _toggleUnitLearnedStatus(unit);
        break;
      case 'delete':
        _deleteUnit(unit);
        break;
    }
  }



  Future<void> _toggleUnitLearnedStatus(Unit unit) async {
    try {
      final updatedUnit = Unit(
        id: unit.id,
        wordbookId: unit.wordbookId,
        name: unit.name,
        description: unit.description,
        wordCount: unit.wordCount,
        isLearned: !unit.isLearned,
        createdAt: unit.createdAt,
        updatedAt: DateTime.now(),
      );
      
      await _unitService.updateUnit(updatedUnit);
      await _loadUnits();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(unit.isLearned ? '已标记为未学习' : '已标记为已学习')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('更新学习状态失败: $e')),
        );
      }
    }
  }

  Future<void> _deleteUnit(Unit unit) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除单元 "${unit.name}" 吗？\n\n注意：删除单元会同时删除其中的所有单词，此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _unitService.deleteUnit(unit.id!);
        await _loadUnits();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('单元已删除')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('删除单元失败: $e')),
          );
        }
      }
    }
  }

  Future<void> _startUnitDictation(String unitName, List<Word> unitWords) async {
    if (unitWords.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('该单元没有单词')),
      );
      return;
    }

    // Show unified dictation config dialog
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => UnifiedDictationConfigDialog(
        totalWords: unitWords.length,
        sourceName: unitName,
        showQuantitySelection: true,
      ),
    );

    if (result == null) return;

    final mode = result['mode'] as int;
    final order = result['order'] as int;
    final quantity = result['quantity'] as int;

    _startUnitDictationWithCount(mode, order, unitWords, quantity);
  }

  void _startUnitDictationWithCount(int mode, int order, List<Word> unitWords, int count) async {
    final wordsToUse = count >= unitWords.length ? unitWords : unitWords.take(count).toList();
    
    try {
      final dictationProvider = Provider.of<DictationProvider>(context, listen: false);
      
      // Load words into dictation provider
      await dictationProvider.loadWordsFromWordbook(
        words: wordsToUse,
        wordbookName: widget.wordbook.name,
        mode: mode,
        order: order,
        count: wordsToUse.length,
      );

      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => const DictationScreen(),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('启动默写失败: $e')),
        );
      }
    }
  }



  void _showUnitWords(String unitName, List<Word> unitWords) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: false,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.8,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            // Handle
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 8, bottom: 4),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Title row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      unitName,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
            // Word count
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${unitWords.length} 个单词',
                  style: TextStyle(
                    color: Colors.grey[600],
                  ),
                ),
              ),
            ),
            // Divider
            const Divider(height: 1),
            // Word list
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: unitWords.length,
                itemBuilder: (context, index) {
                  final word = unitWords[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.blue[100],
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(color: Colors.blue[800]),
                        ),
                      ),
                      title: Text(
                        word.prompt,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(word.answer),
                          if (word.partOfSpeech != null || word.level != null)
                            const SizedBox(height: 4),
                          if (word.partOfSpeech != null || word.level != null)
                            Row(
                              children: [
                                if (word.partOfSpeech != null)
                                  Chip(
                                    label: Text(
                                      word.partOfSpeech!,
                                      style: const TextStyle(fontSize: 10),
                                    ),
                                    backgroundColor: Colors.blue[100],
                                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                if (word.partOfSpeech != null && word.level != null)
                                  const SizedBox(width: 4),
                                if (word.level != null)
                                  Chip(
                                    label: Text(
                                      word.level!,
                                      style: const TextStyle(fontSize: 10),
                                    ),
                                    backgroundColor: Colors.green[100],
                                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                              ],
                            ),
                        ],
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: () => _startWordCopying(word),
                        tooltip: '抄写',
                      ),
                    ),
                  );
                },
              ),
            ),
            // Action buttons
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _startUnitCopying(unitName, unitWords);
                      },
                      icon: const Icon(Icons.edit),
                      label: const Text('抄写'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _startUnitDictation(unitName, unitWords);
                      },
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('默写'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _startWordCopying(Word word) async {
    try {
      final dictationProvider = Provider.of<DictationProvider>(context, listen: false);
      
      // Load single word for copying
      await dictationProvider.loadWordsFromWordbook(
        words: [word],
        wordbookName: widget.wordbook.name,
        mode: 1, // copying mode
        order: 0, // order doesn't matter for single word
        count: 1,
      );

      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => const CopyingScreen(),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('启动抄写失败: $e')),
        );
      }
    }
  }

  Future<void> _startUnitCopying(String unitName, List<Word> unitWords) async {
    if (unitWords.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('该单元没有单词')),
        );
      }
      return;
    }

    try {
      final dictationProvider = Provider.of<DictationProvider>(context, listen: false);
      
      // Load all words in unit for copying
      await dictationProvider.loadWordsFromWordbook(
        words: unitWords,
        wordbookName: widget.wordbook.name,
        mode: 1, // copying mode
        order: 0, // sequential order
        count: unitWords.length,
      );

      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => const CopyingScreen(),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('启动抄写失败: $e')),
        );
      }
    }
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}