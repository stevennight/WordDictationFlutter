import 'package:flutter/material.dart';
import '../../shared/models/wordbook.dart';
import '../../shared/models/word.dart';
import '../../core/services/wordbook_service.dart';
import '../dictation/screens/dictation_screen.dart';
import '../../shared/providers/dictation_provider.dart';
import 'package:provider/provider.dart';

class WordbookDetailScreen extends StatefulWidget {
  final Wordbook wordbook;

  const WordbookDetailScreen({super.key, required this.wordbook});

  @override
  State<WordbookDetailScreen> createState() => _WordbookDetailScreenState();
}

class _WordbookDetailScreenState extends State<WordbookDetailScreen> {
  final WordbookService _wordbookService = WordbookService();
  List<Word> _words = [];
  bool _isLoading = true;
  String _searchQuery = '';
  List<Word> _filteredWords = [];

  @override
  void initState() {
    super.initState();
    _loadWords();
  }

  Future<void> _loadWords() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final words = await _wordbookService.getWordbookWords(widget.wordbook.id!);
      setState(() {
        _words = words;
        _filteredWords = words;
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
      if (query.isEmpty) {
        _filteredWords = _words;
      } else {
        _filteredWords = _words.where((word) {
          return word.prompt.toLowerCase().contains(query.toLowerCase()) ||
                 word.answer.toLowerCase().contains(query.toLowerCase()) ||
                 (word.category?.toLowerCase().contains(query.toLowerCase()) ?? false);
        }).toList();
      }
    });
  }

  Future<void> _startDictation(int mode, int count) async {
    if (_words.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('词书中没有单词')),
      );
      return;
    }

    try {
      final dictationProvider = Provider.of<DictationProvider>(context, listen: false);
      
      // Load words into dictation provider
      await dictationProvider.loadWordsFromWordbook(
        words: _words,
        wordbookName: widget.wordbook.name,
        mode: mode,
        count: count,
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

  void _showDictationOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '选择默写模式',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            
            // Mode selection
            const Text(
              '默写模式:',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _showCountSelection(0); // 中文->英文
                    },
                    child: const Text('中文 → 英文'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _showCountSelection(1); // 英文->中文
                    },
                    child: const Text('英文 → 中文'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _showCountSelection(int mode) {
    final maxCount = _words.length;
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '选择默写数量 (最多 $maxCount 个)',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            
            // Quick selection buttons
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (maxCount >= 10)
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _startDictation(mode, 10);
                    },
                    child: const Text('10 个'),
                  ),
                if (maxCount >= 20)
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _startDictation(mode, 20);
                    },
                    child: const Text('20 个'),
                  ),
                if (maxCount >= 50)
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _startDictation(mode, 50);
                    },
                    child: const Text('50 个'),
                  ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _startDictation(mode, maxCount);
                  },
                  child: Text('全部 ($maxCount 个)'),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.wordbook.name),
        actions: [
          if (_words.isNotEmpty)
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
              decoration: const InputDecoration(
                hintText: '搜索单词...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: _filterWords,
            ),
          ),
          
          // Words list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredWords.isEmpty
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
                              subtitle: Text(word.answer),
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
                      ),
          ),
        ],
      ),
      floatingActionButton: _words.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _showDictationOptions,
              icon: const Icon(Icons.play_arrow),
              label: const Text('开始默写'),
            )
          : null,
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}