import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';

import '../../../shared/models/word.dart';
import '../../../shared/models/dictation_session.dart';
import '../../../shared/providers/dictation_provider.dart';
import '../../../shared/providers/app_state_provider.dart';
import '../../../core/services/word_import_service.dart';
import '../widgets/mode_selection_card.dart';
import '../widgets/quantity_selection_dialog.dart';
import '../widgets/file_drop_zone.dart';
import '../../wordbook/wordbook_management_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final WordImportService _importService = WordImportService();
  bool _isLoading = false;
  String? _statusMessage;
  List<Word> _loadedWords = [];
  String? _fileName;

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
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => const WordbookManagementScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.library_books),
                    label: const Text('管理词书'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => const WordbookManagementScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('导入词书'),
                  ),
                ),
              ],
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
                    '选择默写模式',
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
              Row(
                children: [
                  Expanded(
                    child: ModeSelectionCard(
                      title: '顺序默写',
                      description: '按照原始顺序进行默写',
                      icon: Icons.format_list_numbered,
                      onTap: () => _startDictation(DictationMode.sequential),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ModeSelectionCard(
                      title: '随机默写',
                      description: '随机打乱顺序进行默写',
                      icon: Icons.shuffle,
                      onTap: () => _startDictation(DictationMode.random),
                    ),
                  ),
                ],
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

  Future<void> _startDictation(DictationMode mode) async {
    if (_loadedWords.isEmpty) return;

    // Show quantity selection dialog
    final quantity = await showDialog<int>(
      context: context,
      builder: (context) => QuantitySelectionDialog(
        totalWords: _loadedWords.length,
      ),
    );

    if (quantity == null) return;

    try {
      final dictationProvider = context.read<DictationProvider>();
      final appState = context.read<AppStateProvider>();

      // Start dictation
      await dictationProvider.startDictation(
        mode: mode,
        customQuantity: quantity == -1 ? null : quantity,
        wordFileName: _fileName,
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