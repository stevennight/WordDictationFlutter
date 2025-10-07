import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_word_dictation/shared/models/word_explanation.dart';
import '../../shared/models/wordbook.dart';
import '../../core/services/wordbook_service.dart';
import '../../core/services/ai_example_service.dart';
import '../../core/services/example_sentence_service.dart';
import '../../core/services/config_service.dart';
import '../../core/services/word_explanation_batch_service.dart';
import '../../core/services/ai_word_explanation_service.dart';
import '../../core/services/word_explanation_service.dart';
import '../../shared/models/word.dart';
import 'wordbook_detail_screen.dart';
import 'wordbook_create_screen.dart';
import 'wordbook_import_screen.dart';
import '../sync/sync_settings_screen.dart';
import '../settings/screens/settings_screen.dart';
import '../../shared/widgets/ai_generate_examples_strategy_dialog.dart';
import '../../shared/widgets/ai_generate_explanations_strategy_dialog.dart';

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
                                onSelected: (value) async {
                                  switch (value) {
                                    case 'edit':
                                      _editWordbookName(wordbook);
                                      break;
                                    case 'export':
                                      _exportWordbook(wordbook);
                                      break;
                                    case 'ai_generate_explanations':
                                      await _generateExplanationsForWordbook(wordbook);
                                      break;
                                    case 'generate_examples_wordbook':
                                      await _generateExamplesForWordbook(wordbook);
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
                                    value: 'ai_generate_explanations',
                                    child: ListTile(
                                      leading: Icon(Icons.psychology),
                                      title: Text('AI生成词解'),
                                      contentPadding: EdgeInsets.zero,
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'generate_examples_wordbook',
                                    child: ListTile(
                                      leading: Icon(Icons.auto_awesome),
                                      title: Text('为该词书生成例句'),
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

  Future<void> _generateExplanationsForWordbook(Wordbook wordbook) async {
    final ok = await _ensureAIConfiguredOrRedirect();
    if (!ok) return;

    // 语言选择：自动识别或手动指定（词解）
    String sourceDropdown = 'auto';
    String targetDropdown = 'auto';
    final TextEditingController sourceCustomController = TextEditingController();
    final TextEditingController targetCustomController = TextEditingController();
    final bool langProceed = await showDialog<bool>(
          context: context,
          builder: (context) {
            return StatefulBuilder(
              builder: (context, setState) => AlertDialog(
                title: const Text('选择语言（词解生成）'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: sourceDropdown,
                            items: const [
                              DropdownMenuItem(value: 'auto', child: Text('原文自动识别')),
                              DropdownMenuItem(value: 'ja', child: Text('日语 ja')),
                              DropdownMenuItem(value: 'zh', child: Text('中文 zh')),
                              DropdownMenuItem(value: 'en', child: Text('英语 en')),
                              DropdownMenuItem(value: 'de', child: Text('德语 de')),
                              DropdownMenuItem(value: 'fr', child: Text('法语 fr')),
                              DropdownMenuItem(value: 'ko', child: Text('韩语 ko')),
                              DropdownMenuItem(value: 'custom', child: Text('自定义')),
                            ],
                            onChanged: (v) => setState(() => sourceDropdown = v ?? 'auto'),
                            decoration: const InputDecoration(labelText: '原文语言（常用）'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: targetDropdown,
                            items: const [
                              DropdownMenuItem(value: 'auto', child: Text('译文自动识别')),
                              DropdownMenuItem(value: 'zh', child: Text('中文 zh')),
                              DropdownMenuItem(value: 'ja', child: Text('日语 ja')),
                              DropdownMenuItem(value: 'en', child: Text('英语 en')),
                              DropdownMenuItem(value: 'de', child: Text('德语 de')),
                              DropdownMenuItem(value: 'fr', child: Text('法语 fr')),
                              DropdownMenuItem(value: 'ko', child: Text('韩语 ko')),
                              DropdownMenuItem(value: 'custom', child: Text('自定义')),
                            ],
                            onChanged: (v) => setState(() => targetDropdown = v ?? 'auto'),
                            decoration: const InputDecoration(labelText: '译文语言（常用）'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (sourceDropdown == 'custom')
                      TextField(
                        controller: sourceCustomController,
                        decoration: const InputDecoration(
                          labelText: '原文语言（自定义代码，可选）',
                          hintText: '如 ja, zh-CN, en-US，留空则自动或常用选择',
                        ),
                      ),
                    if (targetDropdown == 'custom')
                      TextField(
                        controller: targetCustomController,
                        decoration: const InputDecoration(
                          labelText: '译文语言（自定义代码，可选）',
                          hintText: '如 zh, en-GB，留空则自动或常用选择',
                        ),
                      ),
                  ],
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('取消')),
                  TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('开始')),
                ],
              ),
            );
          },
        ) ?? false;
    if (!langProceed) return;
    final srcLangBulk = sourceDropdown == 'custom'
        ? (sourceCustomController.text.trim().isEmpty ? null : sourceCustomController.text.trim())
        : (sourceDropdown == 'auto' ? null : sourceDropdown);
    final tgtLangBulk = targetDropdown == 'custom'
        ? (targetCustomController.text.trim().isEmpty ? null : targetCustomController.text.trim())
        : (targetDropdown == 'auto' ? null : targetDropdown);

    final strategy = await pickAIGenerateExplanationsStrategy(context, defaultValue: 'skip');
    final overwrite = strategy == 'overwrite';

    // 计算总数并显示按单词的进度
    final wordsForCount = await _wordbookService.getWordbookWords(wordbook.id!);
    if (wordsForCount.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('词书「${wordbook.name}」没有单词')),
        );
      }
      return;
    }
    final total = wordsForCount.length;
    final processed = ValueNotifier<int>(0);
    final currentWord = ValueNotifier<String>('');
    bool cancelRequested = false;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('为词书「${wordbook.name}」生成词解'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ValueListenableBuilder<int>(
              valueListenable: processed,
              builder: (context, value, _) => LinearProgressIndicator(
                value: total == 0 ? 0 : value / total,
              ),
            ),
            const SizedBox(height: 8),
            ValueListenableBuilder<int>(
              valueListenable: processed,
              builder: (context, value, _) => Text('进度：$value/$total'),
            ),
            const SizedBox(height: 8),
            const Text('正在生成...'),
          ],
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

    try {
      final ai = await AIWordExplanationService.getInstance();
      final expService = WordExplanationService();
      int ok = 0, skipped = 0, fail = 0;
      final cfg = await ConfigService.getInstance();
      final concurrency = await cfg.getAIConcurrency();
      for (int start = 0; start < wordsForCount.length; start += concurrency) {
        final end = (start + concurrency) > wordsForCount.length ? wordsForCount.length : (start + concurrency);
        final futures = <Future<void>>[];
        for (int i = start; i < end; i++) {
          final w = wordsForCount[i];
          futures.add(() async {
            if (cancelRequested) return; // 请求中断后不再启动新的任务
            currentWord.value = w.prompt;

            // 跳过逻辑（若不覆盖且已存在）
            if (!overwrite) {
              final existing = await expService.getByWordId(w.id!);
              if (existing != null) {
                skipped++;
                processed.value = processed.value + 1;
                return;
              }
            }

            try {
              final html = await ai.generateExplanationHtml(
                prompt: w.prompt,
                answer: w.answer,
                sourceLanguage: srcLangBulk,
                targetLanguage: tgtLangBulk,
              );

              final now = DateTime.now();
              final exp = WordExplanation(
                id: null,
                wordId: w.id!,
                html: html,
                sourceModel: null,
                createdAt: now,
                updatedAt: now,
              );

              await expService.upsertForWord(exp);
              ok++;
            } catch (_) {
              fail++;
            } finally {
              processed.value = processed.value + 1;
            }
          }());
        }
        await Future.wait(futures);
        if (cancelRequested) break; // 完成已开始的后结束
      }

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('词解生成完成：成功 $ok，跳过 $skipped，失败 $fail')),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('生成失败：$e')),
        );
      }
    }
  }

  Future<void> _generateExamplesForWordbook(Wordbook wordbook) async {
    final ok = await _ensureAIConfiguredOrRedirect();
    if (!ok) return;

    // 语言选择：自动识别或手动指定（例句）
    String sourceDropdown = 'auto';
    String targetDropdown = 'auto';
    final TextEditingController sourceCustomController = TextEditingController();
    final TextEditingController targetCustomController = TextEditingController();
    final bool langProceed = await showDialog<bool>(
          context: context,
          builder: (context) {
            return StatefulBuilder(
              builder: (context, setState) => AlertDialog(
                title: const Text('选择语言（词书例句）'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: sourceDropdown,
                            items: const [
                              DropdownMenuItem(value: 'auto', child: Text('原文自动识别')),
                              DropdownMenuItem(value: 'ja', child: Text('日语 ja')),
                              DropdownMenuItem(value: 'zh', child: Text('中文 zh')),
                              DropdownMenuItem(value: 'en', child: Text('英语 en')),
                              DropdownMenuItem(value: 'de', child: Text('德语 de')),
                              DropdownMenuItem(value: 'fr', child: Text('法语 fr')),
                              DropdownMenuItem(value: 'ko', child: Text('韩语 ko')),
                              DropdownMenuItem(value: 'custom', child: Text('自定义')),
                            ],
                            onChanged: (v) => setState(() => sourceDropdown = v ?? 'auto'),
                            decoration: const InputDecoration(labelText: '原文语言（常用）'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: targetDropdown,
                            items: const [
                              DropdownMenuItem(value: 'auto', child: Text('译文自动识别')),
                              DropdownMenuItem(value: 'zh', child: Text('中文 zh')),
                              DropdownMenuItem(value: 'ja', child: Text('日语 ja')),
                              DropdownMenuItem(value: 'en', child: Text('英语 en')),
                              DropdownMenuItem(value: 'de', child: Text('德语 de')),
                              DropdownMenuItem(value: 'fr', child: Text('法语 fr')),
                              DropdownMenuItem(value: 'ko', child: Text('韩语 ko')),
                              DropdownMenuItem(value: 'custom', child: Text('自定义')),
                            ],
                            onChanged: (v) => setState(() => targetDropdown = v ?? 'auto'),
                            decoration: const InputDecoration(labelText: '译文语言（常用）'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (sourceDropdown == 'custom')
                      TextField(
                        controller: sourceCustomController,
                        decoration: const InputDecoration(
                          labelText: '原文语言（自定义代码，可选）',
                          hintText: '如 ja, zh-CN, en-US，留空则自动或常用选择',
                        ),
                      ),
                    if (targetDropdown == 'custom')
                      TextField(
                        controller: targetCustomController,
                        decoration: const InputDecoration(
                          labelText: '译文语言（自定义代码，可选）',
                          hintText: '如 zh, en-GB，留空则自动或常用选择',
                        ),
                      ),
                  ],
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('取消')),
                  TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('开始')),
                ],
              ),
            );
          },
        ) ?? false;
    if (!langProceed) return;
    final srcLangBulk = sourceDropdown == 'custom'
        ? (sourceCustomController.text.trim().isEmpty ? null : sourceCustomController.text.trim())
        : (sourceDropdown == 'auto' ? null : sourceDropdown);
    final tgtLangBulk = targetDropdown == 'custom'
        ? (targetCustomController.text.trim().isEmpty ? null : targetCustomController.text.trim())
        : (targetDropdown == 'auto' ? null : targetDropdown);

    final strategy = await pickAIGenerateExamplesStrategy(context, defaultValue: 'append');

    final words = await _wordbookService.getWordbookWords(wordbook.id!);
    if (words.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('词书「${wordbook.name}」没有单词')),
      );
      return;
    }

    bool cancelRequested = false;
    final progress = ValueNotifier<int>(0);
    final total = words.length;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('为词书「${wordbook.name}」生成例句'),
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

      final cfg = await ConfigService.getInstance();
      final concurrency = await cfg.getAIConcurrency();
      for (int start = 0; start < words.length; start += concurrency) {
        final end = (start + concurrency) > words.length ? words.length : (start + concurrency);
        final futures = <Future<void>>[];
        for (int i = start; i < end; i++) {
          final w = words[i];
          futures.add(() async {
            if (cancelRequested) return;

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
              sourceLanguage: srcLangBulk,
              targetLanguage: tgtLangBulk,
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
        SnackBar(content: Text('词书「${wordbook.name}」生成完成：${progress.value}/$total')),
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