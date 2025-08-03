import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';

import '../../../shared/models/word.dart';
import '../../../shared/models/wordbook.dart';
import '../../../shared/models/dictation_session.dart';
import '../../../shared/providers/dictation_provider.dart';
import '../../../shared/providers/app_state_provider.dart';
import '../../../core/services/word_import_service.dart';
import '../../../core/services/wordbook_service.dart';
import '../widgets/mode_selection_card.dart';
import '../widgets/quantity_selection_dialog.dart';
import '../widgets/file_drop_zone.dart';
import '../widgets/home_dictation_mode_dialog.dart';
import '../../wordbook/widgets/wordbook_quantity_selection_dialog.dart';
import '../../wordbook/widgets/dictation_mode_selection_dialog.dart';
import '../../wordbook/wordbook_management_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final WordImportService _importService = WordImportService();
  final WordbookService _wordbookService = WordbookService();
  bool _isLoading = false;
  String? _statusMessage;
  List<Word> _loadedWords = [];
  String? _fileName;
  List<Wordbook> _wordbooks = [];
  bool _isLoadingWordbooks = false;

  @override
  void initState() {
    super.initState();
    _loadWordbooks();
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
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
              ],
            ),
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
              '支持 .xlsx、.docx、.csv 格式\nExcel格式：单词 | 词性 | 中文 | 等级',
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
        allowedExtensions: ['xlsx', 'docx', 'csv'],
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
      } else if (extension == 'docx') {
        words = await _importService.importFromDocx(filePath);
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

      // Organize words by unit
      final Map<String, List<Word>> unitWords = {};
      for (final word in words) {
        final unit = word.category ?? '未分类';
        if (!unitWords.containsKey(unit)) {
          unitWords[unit] = [];
        }
        unitWords[unit]!.add(word);
      }

      // Show selection dialog
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (context) => DraggableScrollableSheet(
          initialChildSize: 0.6,
          maxChildSize: 0.8,
          minChildSize: 0.4,
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
                    itemCount: unitWords.keys.length,
                    itemBuilder: (context, index) {
                      final unitName = unitWords.keys.elementAt(index);
                      final unitWordsList = unitWords[unitName]!;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: Icon(
                            Icons.folder,
                            color: Colors.green[700],
                          ),
                          title: Text(unitName),
                          subtitle: Text('${unitWordsList.length} 个单词'),
                          trailing: const Icon(Icons.play_arrow),
                          onTap: () {
                            Navigator.pop(context);
                            _loadWordsForDictation(unitWordsList, '$unitName (${wordbook.name})');
                          },
                        ),
                      );
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

    _setStatus('已加载：$sourceName，共 ${words.length} 个单词');
  }

  Future<void> _startDictationWithSettings() async {
    if (_loadedWords.isEmpty) return;

    // Step 1: Show quantity selection dialog
    final quantity = await showDialog<int>(
      context: context,
      builder: (context) => WordbookQuantitySelectionDialog(
        totalWords: _loadedWords.length,
      ),
    );

    if (quantity == null) return;

    // Step 2: Show mode and order selection dialog
    final modeResult = await showDialog<Map<String, int>>(
      context: context,
      builder: (context) => DictationModeSelectionDialog(
        quantity: quantity == -1 ? _loadedWords.length : quantity,
        unitName: _fileName ?? '已导入单词',
      ),
    );

    if (modeResult == null) return;

    final mode = modeResult['mode']!;
    final order = modeResult['order']!;
    final finalQuantity = quantity == -1 ? _loadedWords.length : quantity;

    try {
      final dictationProvider = context.read<DictationProvider>();
      final appState = context.read<AppStateProvider>();

      // Load words into dictation provider
      await dictationProvider.loadWordsFromWordbook(
        words: _loadedWords,
        wordbookName: _fileName ?? '已导入单词',
        mode: mode,
        order: order,
        count: finalQuantity,
      );

      // Enter dictation mode
      appState.enterDictationMode(
        wordFileName: _fileName ?? '已导入单词',
        totalWords: finalQuantity,
      );
    } catch (e) {
      _setStatus('开始默写失败: $e');
    }
  }

  Future<void> _startDictation(DictationMode mode) async {
    if (_loadedWords.isEmpty) return;

    // Show mode selection dialog
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => HomeDictationModeDialog(
        totalWords: _loadedWords.length,
        initialMode: mode,
      ),
    );

    if (result == null) return;

    final selectedMode = result['mode'] as DictationMode;
    final dictationDirection = result['mode'] as int; // 获取默写方向
    final quantity = result['quantity'] as int;
 
    try {
      final dictationProvider = context.read<DictationProvider>();
      final appState = context.read<AppStateProvider>();

      // Start dictation
      await dictationProvider.startDictation(
        mode: selectedMode,
        customQuantity: quantity == -1 ? null : quantity,
        wordFileName: _fileName,
        dictationDirection: dictationDirection,
      );

      // Enter dictation mode
      appState.enterDictationMode(
        wordFileName: _fileName ?? '未知文件',
        totalWords: quantity == -1 ? _loadedWords.length : quantity,
      );
    } catch (e) {
      _setStatus('开始默写失败: $e');
    }
  }
}