import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../shared/models/wordbook.dart';
import '../../core/services/wordbook_service.dart';
import '../../core/services/ai_example_service.dart';
import '../../core/services/example_sentence_service.dart';
import '../../core/services/config_service.dart';
import '../../shared/models/word.dart';
import 'wordbook_detail_screen.dart';
import 'wordbook_create_screen.dart';
import 'wordbook_import_screen.dart';
import '../sync/sync_settings_screen.dart';
import '../settings/screens/settings_screen.dart';

class WordbookManagementScreen extends StatefulWidget {
  const WordbookManagementScreen({super.key});

  @override
  State<WordbookManagementScreen> createState() => _WordbookManagementScreenState();
}

class _WordbookManagementScreenState extends State<WordbookManagementScreen> {
  final WordbookService _wordbookService = WordbookService();
  List<Wordbook> _wordbooks = [];
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadWordbooks();
  }

  Future<void> _loadWordbooks() async {
    setState(() {
      _isLoading = true;
    });

    try {
      List<Wordbook> wordbooks;
      if (_searchQuery.isEmpty) {
        wordbooks = await _wordbookService.getAllWordbooks();
      } else {
        wordbooks = await _wordbookService.searchWordbooks(_searchQuery);
      }
      
      // 更新每个词书的单词数量以确保数据准确
      for (final wordbook in wordbooks) {
        if (wordbook.id != null) {
          await _wordbookService.updateWordbookWordCount(wordbook.id!);
        }
      }
      
      // 重新获取更新后的词书列表
      if (_searchQuery.isEmpty) {
        wordbooks = await _wordbookService.getAllWordbooks();
      } else {
        wordbooks = await _wordbookService.searchWordbooks(_searchQuery);
      }
      
      setState(() {
        _wordbooks = wordbooks;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载词书失败: $e')),
        );
      }
    }
  }

  Future<void> _deleteWordbook(Wordbook wordbook) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除词书'),
        content: Text('确定要删除词书「${wordbook.name}」吗？\n\n此操作将同时删除词书中的所有单词，且无法撤销。'),
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
        await _wordbookService.deleteWordbook(wordbook.id!);
        _loadWordbooks();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('词书「${wordbook.name}」已删除')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('删除失败: $e')),
          );
        }
      }
    }
  }

  Future<void> _editWordbookName(Wordbook wordbook) async {
    final controller = TextEditingController(text: wordbook.name);
    final descriptionController = TextEditingController(text: wordbook.description ?? '');

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('编辑词书'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: '词书名称',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: descriptionController,
              decoration: const InputDecoration(
                labelText: '描述（可选）',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                Navigator.of(context).pop({
                  'name': name,
                  'description': descriptionController.text.trim(),
                });
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );

    if (result != null) {
      try {
        final updatedWordbook = wordbook.copyWith(
          name: result['name']!,
          description: result['description']!.isEmpty ? null : result['description'],
          updatedAt: DateTime.now(),
        );
        await _wordbookService.updateWordbook(updatedWordbook);
        _loadWordbooks();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('词书信息已更新')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('更新失败: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('词书管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () async {
              final result = await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const WordbookCreateScreen(),
                ),
              );
              if (result == true) {
                _loadWordbooks();
              }
            },
            tooltip: '创建词书',
          ),
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'import') {
                final result = await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const WordbookImportScreen(),
                  ),
                );
                if (result == true) {
                  _loadWordbooks();
                }
              } else if (value == 'sync') {
                final result = await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const SyncSettingsScreen(),
                  ),
                );
                if (result == true) {
                  _loadWordbooks();
                }
              } else if (value == 'generate_examples_wordbook') {
                await _generateExamplesForWholeWordbook();
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(
                value: 'import',
                child: ListTile(
                  leading: Icon(Icons.upload),
                  title: Text('导入词书'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem<String>(
                value: 'generate_examples_wordbook',
                child: ListTile(
                  leading: Icon(Icons.auto_awesome),
                  title: Text('为整本生成例句'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem<String>(
                value: 'sync',
                child: ListTile(
                  leading: Icon(Icons.sync),
                  title: Text('同步设置'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              decoration: const InputDecoration(
                hintText: '搜索词书...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
                _loadWordbooks();
              },
            ),
          ),
          // Wordbook list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _wordbooks.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.book_outlined,
                              size: 64,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _searchQuery.isEmpty ? '还没有词书' : '没有找到匹配的词书',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _searchQuery.isEmpty ? '点击右上角的 + 按钮创建词书' : '尝试其他搜索关键词',
                              style: TextStyle(
                                color: Colors.grey[500],
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _wordbooks.length,
                        itemBuilder: (context, index) {
                          final wordbook = _wordbooks[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Theme.of(context).primaryColor,
                                child: Text(
                                  wordbook.name.isNotEmpty ? wordbook.name[0].toUpperCase() : 'W',
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                              title: Text(
                                wordbook.name,
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (wordbook.description != null && wordbook.description!.isNotEmpty)
                                    Text(
                                      wordbook.description!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  Text(
                                    '${wordbook.wordCount} 个单词 • ${_formatDate(wordbook.createdAt)}',
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                              trailing: PopupMenuButton<String>(
                                onSelected: (value) {
                                  switch (value) {
                                    case 'edit':
                                      _editWordbookName(wordbook);
                                      break;
                                    case 'export':
                                      _exportWordbook(wordbook);
                                      break;
                                    case 'delete':
                                      _deleteWordbook(wordbook);
                                      break;
                                  }
                                },
                                itemBuilder: (context) => [
                                  const PopupMenuItem(
                                    value: 'edit',
                                    child: ListTile(
                                      leading: Icon(Icons.edit),
                                      title: Text('编辑'),
                                      contentPadding: EdgeInsets.zero,
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'export',
                                    child: ListTile(
                                      leading: Icon(Icons.download),
                                      title: Text('导出词书'),
                                      contentPadding: EdgeInsets.zero,
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: ListTile(
                                      leading: Icon(Icons.delete, color: Colors.red),
                                      title: Text('删除', style: TextStyle(color: Colors.red)),
                                      contentPadding: EdgeInsets.zero,
                                    ),
                                  ),
                                ],
                              ),
                              onTap: () async {
                                final result = await Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (context) => WordbookDetailScreen(wordbook: wordbook),
                                  ),
                                );
                                if (result == true) {
                                  _loadWordbooks();
                                }
                              },
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Future<bool> _ensureAIConfiguredOrRedirect() async {
    final config = await ConfigService.getInstance();
    final apiKey = await config.getAIApiKey();
    final endpoint = await config.getAIEndpoint();
    if (apiKey.isEmpty || endpoint.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请先在设置页配置 AI 的 API Key 和 Endpoint')),
        );
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (context) => const SettingsScreen()),
        );
      }
      return false;
    }
    return true;
  }

  Future<void> _generateExamplesForWholeWordbook() async {
    if (_wordbooks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有可用的词书')),
      );
      return;
    }

    // 选择目标词书与策略
    Wordbook? selected = _wordbooks.first;
    String strategy = 'append';
    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('为整本生成例句'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButton<Wordbook>(
                    value: selected,
                    isExpanded: true,
                    items: _wordbooks.map((wb) {
                      return DropdownMenuItem<Wordbook>(
                        value: wb,
                        child: Text(wb.name),
                      );
                    }).toList(),
                    onChanged: (wb) => setState(() => selected = wb),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: const Text('策略：')),
                      ChoiceChip(
                        label: const Text('追加'),
                        selected: strategy == 'append',
                        onSelected: (_) => setState(() => strategy = 'append'),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('覆盖'),
                        selected: strategy == 'overwrite',
                        onSelected: (_) => setState(() => strategy = 'overwrite'),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('跳过'),
                        selected: strategy == 'skip',
                        onSelected: (_) => setState(() => strategy = 'skip'),
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('取消'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('开始'),
                ),
              ],
            );
          },
        );
      },
    );

    if (proceed != true || selected == null) return;

    final ok = await _ensureAIConfiguredOrRedirect();
    if (!ok) return;

    final words = await _wordbookService.getWordbookWords(selected!.id!);
    if (words.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('词书「${selected!.name}」没有单词')),
      );
      return;
    }

    // 进度与可中断对话框
    bool cancelRequested = false;
    final progress = ValueNotifier<int>(0);
    final total = words.length;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('为词书「${selected!.name}」生成例句'),
        content: ValueListenableBuilder<int>(
          valueListenable: progress,
          builder: (context, processed, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(value: total == 0 ? 0 : processed / total),
              const SizedBox(height: 8),
              Text('进度：$processed / $total'),
            ],
          ),
        ),
        actions: [
          StatefulBuilder(
            builder: (context, setState) => TextButton(
              onPressed: cancelRequested
                  ? null
                  : () => setState(() => cancelRequested = true),
              child: const Text('中断'),
            ),
          ),
        ],
      ),
    );

    final ai = await AIExampleService.getInstance();
    final exService = ExampleSentenceService();

    try {
      if (strategy == 'overwrite') {
        final ids = words.map((w) => w.id!).toList();
        await exService.deleteByWordIds(ids);
      }

      // 按单词并行处理整本词书，按“单词”粒度更新进度
      // 并行度：从设置读取，替代硬编码
      final cfg = await ConfigService.getInstance();
      final concurrency = await cfg.getAIConcurrency();
      for (int start = 0; start < words.length; start += concurrency) {
        final end = (start + concurrency) > words.length ? words.length : (start + concurrency);
        final futures = <Future<void>>[];
        for (int i = start; i < end; i++) {
          final w = words[i];
          futures.add(() async {
            if (cancelRequested) return; // 用户请求中断时跳过后续任务

            if (strategy == 'skip') {
              final existing = await exService.getExamplesByWordId(w.id!);
              if (existing.isNotEmpty) {
                progress.value = progress.value + 1;
                return;
              }
            }

            final examples = await ai.generateExamples(
              prompt: w.prompt,
              answer: w.answer,
              sourceLanguage: null,
              targetLanguage: null,
            );

            final withWordId = examples.map((e) => e.copyWith(wordId: w.id)).toList();
            await exService.insertExamples(withWordId);

            progress.value = progress.value + 1;
          }());
        }
        await Future.wait(futures);
        if (cancelRequested) break;
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('生成失败：$e')),
        );
      }
      return;
    }

    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('词书「${selected!.name}」生成完成：${progress.value}/$total')),
      );
    }
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Future<void> _exportWordbook(Wordbook wordbook) async {
    try {
      final jsonString = await _wordbookService.exportSingleWordbook(wordbook.id!);

      final now = DateTime.now();
      final timestamp = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
      final String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: '请选择保存导出的文件',
        fileName: '${wordbook.name}_export_$timestamp.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: utf8.encode(jsonString),
      );

      if (outputFile != null) {
        final file = File(outputFile);
        await file.writeAsString(jsonString);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('词书「${wordbook.name}」已成功导出到: $outputFile')),
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
}