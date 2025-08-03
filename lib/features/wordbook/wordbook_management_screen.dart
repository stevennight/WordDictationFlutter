import 'package:flutter/material.dart';
import '../../shared/models/wordbook.dart';
import '../../core/services/wordbook_service.dart';
import 'wordbook_detail_screen.dart';
import 'wordbook_create_screen.dart';
import 'wordbook_import_screen.dart';
import '../sync/sync_settings_screen.dart';

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
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const SyncSettingsScreen(),
                  ),
                );
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
                                onSelected: (value) {
                                  switch (value) {
                                    case 'edit':
                                      _editWordbookName(wordbook);
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

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}