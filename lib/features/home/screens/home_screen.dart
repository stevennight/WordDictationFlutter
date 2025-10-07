import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/services/unit_service.dart';
import '../../../core/services/word_import_service.dart';
import '../../../core/services/wordbook_service.dart';
import '../../../shared/models/unit.dart';
import 'package:flutter_word_dictation/shared/models/word.dart';
import '../../../shared/models/wordbook.dart';
import '../../../shared/providers/app_state_provider.dart';
import '../../../shared/providers/dictation_provider.dart';
import '../../../shared/widgets/unified_dictation_config_dialog.dart';
import '../../wordbook/wordbook_management_screen.dart';
import '../widgets/file_drop_zone.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final WordImportService _importService = WordImportService();
  final WordbookService _wordbookService = WordbookService();
  final UnitService _unitService = UnitService();
  bool _isLoading = false;
  String? _statusMessage;
  List<Word> _loadedWords = [];
  String? _fileName;
  List<Wordbook> _wordbooks = [];
  bool _isLoadingWordbooks = false;
  int _lastWordbookUpdateCounter = -1;

  @override
  void initState() {
    super.initState();
    _loadWordbooks();
  }
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 监听词书更新状态
    final appState = context.watch<AppStateProvider>();
    if (appState.wordbookUpdateCounter != _lastWordbookUpdateCounter) {
      _lastWordbookUpdateCounter = appState.wordbookUpdateCounter;
      if (_lastWordbookUpdateCounter > 0) {
        // 延迟刷新，避免在build过程中调用setState
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _loadWordbooks();
        });
      }
    }
  }

  Future<void> _loadWordbooks() async {
    setState(() {
      _isLoadingWordbooks = true;
    });

    try {
      final wordbooks = await _wordbookService.getAllWordbooks();
      setState(() {
        _wordbooks = wordbooks;
        _isLoadingWordbooks = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingWordbooks = false;
      });
    }
  }

  void _setStatus(String message) {
    setState(() {
      _statusMessage = message;
    });

    // Auto clear status after 5 seconds
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) {
        setState(() {
          _statusMessage = null;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Consumer2<DictationProvider, AppStateProvider>(
        builder: (context, dictationProvider, appState, child) {
          return CustomScrollView(
            slivers: [
              SliverAppBar(
                title: const Text('首页'),
                floating: true,
                snap: true,
                backgroundColor: Theme.of(context).colorScheme.surface,
                foregroundColor: Theme.of(context).colorScheme.onSurface,
                surfaceTintColor: Theme.of(context).colorScheme.primary,
              ),
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _buildWelcomeSection(),
                    const SizedBox(height: 24),
                    _buildWordbookSection(),
                    const SizedBox(height: 24),
                    if (_wordbooks.isNotEmpty) _buildQuickStartSection(),
                    if (_wordbooks.isNotEmpty) const SizedBox(height: 24),
                    _buildFileImportSection(),
                    const SizedBox(height: 24),
                    if (_loadedWords.isNotEmpty) ..._buildModeSelectionSection(),
                    if (_statusMessage != null) ..._buildStatusSection(),
                  ]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildWordbookSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.library_books,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  '词书管理',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              '管理您的词书，从词书中选择单词进行默写练习',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const WordbookManagementScreen(),
                  ),
                ).then((_) => _loadWordbooks()); // 返回时刷新词书列表
              },
              icon: const Icon(Icons.library_books),
              label: const Text('管理词书'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomeSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(
              Icons.edit_note,
              size: 64,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              '欢迎使用默写小助手',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '管理词书或导入单词文件开始练习',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileImportSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.file_upload,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  '导入单词文件',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 16),
            FileDropZone(
              onFileSelected: _handleFileSelected,
              isLoading: _isLoading,
              fileName: _fileName,
              wordCount: _loadedWords.length,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _pickFile,
                    icon: const Icon(Icons.folder_open),
                    label: const Text('选择文件'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _loadedWords.isEmpty ? null : _clearWords,
                    icon: const Icon(Icons.clear),
                    label: const Text('清空'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '支持 .xlsx、.csv 格式\nExcel格式：单词 | 词性 | 中文 | 等级',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildModeSelectionSection() {
    return [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.play_arrow,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '开始默写',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                '已加载 ${_loadedWords.length} 个单词',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: _startDictationWithSettings,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text(
                    '开始默写',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ];
  }

  List<Widget> _buildStatusSection() {
    return [
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _statusMessage!.contains('成功')
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              _statusMessage!.contains('成功') ? Icons.check_circle : Icons.error,
              color: _statusMessage!.contains('成功')
                  ? Theme.of(context).colorScheme.onPrimaryContainer
                  : Theme.of(context).colorScheme.onErrorContainer,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _statusMessage!,
                style: TextStyle(
                  color: _statusMessage!.contains('成功')
                      ? Theme.of(context).colorScheme.onPrimaryContainer
                      : Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    ];
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'csv'],
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        if (file.path != null) {
          await _handleFileSelected(file.path!);
        }
      }
    } catch (e) {
      _setStatus('选择文件失败: $e');
    }
  }

  Future<void> _handleFileSelected(String filePath) async {
    setState(() {
      _isLoading = true;
      _statusMessage = null;
    });

    try {
      List<Word> words;
      final extension = filePath.split('.').last.toLowerCase();
      
      if (extension == 'xlsx') {
        words = await _importService.importFromExcel(filePath);
      } else if (extension == 'csv') {
        words = await _importService.importFromCsv(filePath);
      } else {
        throw Exception('不支持的文件格式');
      }
      
      setState(() {
        _loadedWords = words;
        _fileName = filePath.split('/').last.split('\\').last;
        _statusMessage = '成功加载 ${words.length} 个单词';
      });

      // Load words into dictation provider
      final dictationProvider = context.read<DictationProvider>();
      await dictationProvider.loadWords(words);
    } catch (e) {
      _setStatus('导入文件失败: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _clearWords() {
    setState(() {
      _loadedWords.clear();
      _fileName = null;
      _statusMessage = null;
    });

    final dictationProvider = context.read<DictationProvider>();
    dictationProvider.reset();
  }

  Widget _buildQuickStartSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.flash_on,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  '快速开始',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              '从已有词书中选择单词进行默写练习',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            if (_isLoadingWordbooks)
              const Center(child: CircularProgressIndicator())
            else
              ..._wordbooks.map((wordbook) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Card(
                  elevation: 1,
                  child: ListTile(
                    leading: Icon(
                      Icons.book,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    title: Text(wordbook.name),
                    subtitle: Text('${wordbook.wordCount} 个单词'),
                    trailing: const Icon(Icons.arrow_forward_ios),
                    onTap: () => _selectWordbookForDictation(wordbook),
                  ),
                ),
              )),
          ],
        ),
      ),
    );
  }

  Future<void> _selectWordbookForDictation(Wordbook wordbook) async {
    try {
      final words = await _wordbookService.getWordbookWords(wordbook.id!);
      if (words.isEmpty) {
        _setStatus('词书中没有单词');
        return;
      }

      // Get units from UnitService
      final units = await _unitService.getUnitsByWordbookId(wordbook.id!);
      
      // Organize words by unit using unit ID
      final Map<Unit, List<Word>> unitWordsMap = {};
      final List<Word> unassignedWords = [];
      
      // Initialize unit maps
      for (final unit in units) {
        unitWordsMap[unit] = [];
      }
      
      // Assign words to units
      for (final word in words) {
        if (word.unitId != null) {
          final unit = units.where((u) => u.id == word.unitId).firstOrNull;
          if (unit != null) {
            unitWordsMap[unit]!.add(word);
          } else {
            unassignedWords.add(word);
          }
        } else {
          unassignedWords.add(word);
        }
      }
      
      // Sort units by name
      final sortedUnits = units.toList()..sort((a, b) => a.name.compareTo(b.name));

      // Show selection dialog
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (context) => DraggableScrollableSheet(
          initialChildSize: 1,
          maxChildSize: 1,
          minChildSize: 1,
          builder: (context, scrollController) => Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '选择默写内容 - ${wordbook.name}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Option to select entire wordbook
                Card(
                  child: ListTile(
                    leading: Icon(
                      Icons.book,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    title: const Text('整本词书'),
                    subtitle: Text('${words.length} 个单词'),
                    trailing: const Icon(Icons.play_arrow),
                    onTap: () {
                      Navigator.pop(context);
                      _loadWordsForDictation(words, wordbook.name);
                    },
                  ),
                ),
                // 仅已学习单元选项
                if (sortedUnits.any((unit) => unit.isLearned))
                  Card(
                    child: ListTile(
                      leading: Icon(Icons.check_circle, color: Colors.green[700]),
                      title: const Text('仅已学习单元'),
                      subtitle: Text('${sortedUnits.where((unit) => unit.isLearned).fold(0, (sum, unit) => sum + (unitWordsMap[unit]?.length ?? 0))} 个单词'),
                      trailing: const Icon(Icons.play_arrow),
                      onTap: () {
                        Navigator.pop(context);
                        final learnedWords = sortedUnits
                            .where((unit) => unit.isLearned)
                            .expand((unit) => unitWordsMap[unit] ?? <Word>[])
                            .toList();
                        _loadWordsForDictation(learnedWords, '${wordbook.name} (仅已学习单元)');
                      },
                    ),
                  ),
                const SizedBox(height: 8),
                const Divider(),
                const SizedBox(height: 8),
                Text(
                  '或选择单元',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: sortedUnits.length + (unassignedWords.isNotEmpty ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index < sortedUnits.length) {
                        final unit = sortedUnits[index];
                        final unitWordsList = unitWordsMap[unit]!;
                        
                        // Skip empty units
                        if (unitWordsList.isEmpty) {
                          return const SizedBox.shrink();
                        }
                        
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: Icon(
                              Icons.folder,
                              color: unit.isLearned ? Colors.green[700] : Colors.blue[700],
                            ),
                            title: Row(
                              children: [
                                Expanded(child: Text(unit.name)),
                                if (unit.isLearned)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.green[100],
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      '已学完',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.green[700],
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            subtitle: Text('${unitWordsList.length} 个单词'),
                            trailing: const Icon(Icons.play_arrow),
                            onTap: () {
                              Navigator.pop(context);
                              _loadWordsForDictation(unitWordsList, '${unit.name} (${wordbook.name})');
                            },
                          ),
                        );
                      } else {
                        // Show unassigned words
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: Icon(
                              Icons.folder_open,
                              color: Colors.grey[600],
                            ),
                            title: const Text('未分类单词'),
                            subtitle: Text('${unassignedWords.length} 个单词'),
                            trailing: const Icon(Icons.play_arrow),
                            onTap: () {
                              Navigator.pop(context);
                              _loadWordsForDictation(unassignedWords, '未分类单词 (${wordbook.name})');
                            },
                          ),
                        );
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      _setStatus('加载词书失败: $e');
    }
  }

  Future<void> _loadWordsForDictation(List<Word> words, String sourceName) async {
    setState(() {
      _loadedWords = words;
      _fileName = sourceName;
    });

    // Load words into dictation provider
    final dictationProvider = context.read<DictationProvider>();
    await dictationProvider.loadWords(words);

    // _setStatus('已加载：$sourceName，共 ${words.length} 个单词');
  }

  Future<void> _startDictationWithSettings() async {
    if (_loadedWords.isEmpty) return;

    // Show unified dictation config dialog
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => UnifiedDictationConfigDialog(
        totalWords: _loadedWords.length,
        sourceName: _fileName ?? '已导入单词',
        showQuantitySelection: true,
      ),
    );

    if (result == null) return;

    final mode = result['mode'] as int;
    final order = result['order'] as int;
    final quantity = result['quantity'] as int;

    try {
      final dictationProvider = context.read<DictationProvider>();
      final appState = context.read<AppStateProvider>();

      // Load words into dictation provider
      await dictationProvider.loadWordsFromWordbook(
        words: _loadedWords,
        wordbookName: _fileName ?? '已导入单词',
        mode: mode,
        order: order,
        count: quantity,
      );

      // Enter dictation mode
      appState.enterDictationMode(
        wordFileName: _fileName ?? '已导入单词',
        totalWords: quantity,
      );
    } catch (e) {
      _setStatus('开始默写失败: $e');
    }
  }

}