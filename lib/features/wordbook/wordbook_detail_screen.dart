import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../shared/models/word.dart';
import '../../shared/models/wordbook.dart';
import '../../shared/models/dictation_session.dart';
import '../../shared/providers/dictation_provider.dart';
import '../../core/services/wordbook_service.dart';
import 'unit_management_screen.dart';
import '../dictation/screens/dictation_screen.dart';
import 'widgets/wordbook_quantity_selection_dialog.dart';
import 'widgets/dictation_mode_selection_dialog.dart';

class WordbookDetailScreen extends StatefulWidget {
  final Wordbook wordbook;

  const WordbookDetailScreen({super.key, required this.wordbook});

  @override
  State<WordbookDetailScreen> createState() => _WordbookDetailScreenState();
}

class _WordbookDetailScreenState extends State<WordbookDetailScreen> {
  final WordbookService _wordbookService = WordbookService();
  List<Word> _words = [];
  Map<String, List<Word>> _unitWords = {};
  bool _isLoading = true;
  String _searchQuery = '';
  List<Word> _filteredWords = [];
  List<String> _filteredUnits = [];
  bool _isWordView = true; // true for word view, false for unit view
  String? _selectedUnit; // 选中的单元，null表示显示所有单元

  @override
  void initState() {
    super.initState();
    _loadWords();
  }

  void _organizeWordsByUnit() {
    _unitWords.clear();
    for (final word in _words) {
      final unit = word.category ?? '未分类';
      if (!_unitWords.containsKey(unit)) {
        _unitWords[unit] = [];
      }
      _unitWords[unit]!.add(word);
    }
  }

  void _filterUnits() {
    if (_searchQuery.isEmpty) {
      _filteredUnits = _unitWords.keys.toList();
    } else {
      _filteredUnits = _unitWords.keys
          .where((unit) => unit.toLowerCase().contains(_searchQuery.toLowerCase()))
          .toList();
    }
    _filteredUnits.sort();
  }

  Future<void> _loadWords() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final words = await _wordbookService.getWordbookWords(widget.wordbook.id!);
      setState(() {
        _words = words;
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
          SnackBar(content: Text('加载单词失败: $e')),
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
    final wordsToUse = _filteredWords.isNotEmpty ? _filteredWords : _words;
    if (wordsToUse.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有可用的单词')),
      );
      return;
    }

    // Step 1: Select quantity
    final quantity = await showDialog<int>(
      context: context,
      builder: (context) => WordbookQuantitySelectionDialog(
        totalWords: wordsToUse.length,
        unitName: _selectedUnit,
      ),
    );

    if (quantity == null) return;

    // Step 2: Select mode and order
    final result = await showDialog<Map<String, int>>(
      context: context,
      builder: (context) => DictationModeSelectionDialog(
        quantity: quantity == -1 ? wordsToUse.length : quantity,
        unitName: _selectedUnit,
      ),
    );

    if (result == null) return;

    final mode = result['mode']!;
    final order = result['order']!;
    final finalQuantity = quantity == -1 ? wordsToUse.length : quantity;

    _startFilteredDictation(mode, order, wordsToUse, finalQuantity);
  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.wordbook.name),
        actions: [
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
          IconButton(
            icon: const Icon(Icons.folder_open),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => UnitManagementScreen(wordbook: widget.wordbook),
                ),
              ).then((_) => _loadWords()); // 返回时刷新数据
            },
            tooltip: '单元管理',
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
                      '${widget.wordbook.wordCount} 个单词',
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
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => UnitManagementScreen(wordbook: widget.wordbook),
                        ),
                      ).then((_) => _loadWords());
                    },
                    icon: const Icon(Icons.folder_open),
                    label: const Text('进入单元管理'),
                  ),
                ]
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
                  trailing: word.category != null
                      ? Chip(
                          label: Text(
                            word.category!,
                            style: const TextStyle(fontSize: 12),
                          ),
                          backgroundColor: Colors.grey[200],
                        )
                      : null,
                ),
              );
            },
          );
  }

  Widget _buildUnitsList() {
    return _filteredUnits.isEmpty
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
                    '点击右上角的文件夹图标进入单元管理',
                    style: TextStyle(
                      color: Colors.grey[500],
                    ),
                  ),
                ]
              ],
            ),
          )
        : ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _filteredUnits.length,
            itemBuilder: (context, index) {
              final unitName = _filteredUnits[index];
              final unitWords = _unitWords[unitName]!;
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.green[100],
                    child: Icon(
                      Icons.folder,
                      color: Colors.green[800],
                    ),
                  ),
                  title: Text(
                    unitName,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text('${unitWords.length} 个单词'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.play_arrow),
                        onPressed: () => _startUnitDictation(unitName, unitWords),
                        tooltip: '开始默写',
                      ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                  onTap: () => _showUnitWords(unitName, unitWords),
                ),
              );
            },
          );
  }

  Future<void> _startUnitDictation(String unitName, List<Word> unitWords) async {
    if (unitWords.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('该单元没有单词')),
      );
      return;
    }

    // Step 1: Select quantity
    final quantity = await showDialog<int>(
      context: context,
      builder: (context) => WordbookQuantitySelectionDialog(
        totalWords: unitWords.length,
        unitName: unitName,
      ),
    );

    if (quantity == null) return;

    // Step 2: Select mode and order
    final result = await showDialog<Map<String, int>>(
      context: context,
      builder: (context) => DictationModeSelectionDialog(
        quantity: quantity == -1 ? unitWords.length : quantity,
        unitName: unitName,
      ),
    );

    if (result == null) return;

    final mode = result['mode']!;
    final order = result['order']!;
    final finalQuantity = quantity == -1 ? unitWords.length : quantity;

    _startUnitDictationWithCount(mode, order, unitWords, finalQuantity);
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
                    ),
                  );
                },
              ),
            ),
            // Start dictation button
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _startUnitDictation(unitName, unitWords);
                  },
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('开始默写'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}