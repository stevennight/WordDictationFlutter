import 'package:flutter/material.dart';
import 'package:flutter_word_dictation/core/models/dictionary.dart';
import 'package:flutter_word_dictation/core/services/dictionary_service.dart';
import 'package:flutter_word_dictation/core/services/dictionary_query_service.dart';
import 'dictionary_entry_screen.dart';

class DictKeyItem {
  final Dictionary dictionary;
  final String key;
  const DictKeyItem(this.dictionary, this.key);
}

class DictionaryQueryScreen extends StatefulWidget {
  final String? initialQuery;

  const DictionaryQueryScreen({super.key, this.initialQuery});

  @override
  State<DictionaryQueryScreen> createState() => _DictionaryQueryScreenState();
}

class _DictionaryQueryScreenState extends State<DictionaryQueryScreen> {
  final DictionaryService _dictionaryService = DictionaryService();
  final DictionaryQueryService _queryService = DictionaryQueryService();
  final TextEditingController _controller = TextEditingController();
  List<Dictionary> _dictionaries = [];
  int _selectedDictionaryIndex = -1;
  bool _loading = false;
  List<DictKeyItem> _entries = [];

  @override
  void initState() {
    super.initState();
    _loadDictionaries();
    final q = widget.initialQuery?.trim() ?? '';
    if (q.isNotEmpty) {
      _controller.text = q;
    }
  }

  @override
  void dispose() {
    _queryService.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadDictionaries() async {
    final ds = await _dictionaryService.getDictionaries();
    if (mounted) {
      setState(() {
        _dictionaries = ds;
        if (_dictionaries.isNotEmpty && _selectedDictionaryIndex >= _dictionaries.length) {
          _selectedDictionaryIndex = -1;
        }
      });
    }
    final q = _controller.text.trim();
    if (q.isNotEmpty) {
      _doSearch(q);
    }
  }

  void _changeDictionaryIndex(int? index) {
    setState(() {
      _selectedDictionaryIndex = index ?? -1;
    });
    final q = _controller.text.trim();
    if (q.isNotEmpty) {
      _doSearch(q);
    }
  }

  void _doSearch(String text) async {
    final word = text.trim();
    if (word.isEmpty || _dictionaries.isEmpty) {
      setState(() {
        _entries = [];
      });
      return;
    }
    setState(() {
      _loading = true;
      _entries = [];
    });

    if (_selectedDictionaryIndex == -1) {
      final List<DictKeyItem> entries = [];
      for (final d in _dictionaries) {
        final keys = await _queryService.searchKeys(d, word, limit: 50);
        for (final k in keys) {
          entries.add(DictKeyItem(d, k));
        }
      }
      if (mounted) {
        setState(() {
          _entries = entries;
          _loading = false;
        });
      }
    } else {
      final dictionary = _dictionaries[_selectedDictionaryIndex];
      final keys = await _queryService.searchKeys(dictionary, word, limit: 50);
      if (mounted) {
        setState(() {
          _entries = keys.map((k) => DictKeyItem(dictionary, k)).toList();
          _loading = false;
        });
      }
    }
  }

  void _openEntry(DictKeyItem item) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => DictionaryEntryScreen(dictionary: item.dictionary, entryKey: item.key),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('词典查询'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_dictionaries.isNotEmpty)
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _selectedDictionaryIndex,
                      items: [
                        const DropdownMenuItem<int>(value: -1, child: Text('所有词典')),
                        for (int i = 0; i < _dictionaries.length; i++)
                          DropdownMenuItem<int>(value: i, child: Text(_dictionaries[i].name)),
                      ],
                      onChanged: _changeDictionaryIndex,
                      decoration: const InputDecoration(
                        labelText: '选择词典',
                      ),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              decoration: InputDecoration(
                hintText: '输入要查询的单词',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () => _doSearch(_controller.text),
                ),
              ),
              onSubmitted: _doSearch,
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(8.0),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (_entries.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('匹配项', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _entries.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        final item = _entries[index];
                        return ListTile(
                          dense: true,
                          title: Text(item.key),
                          subtitle: Text(item.dictionary.name),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _openEntry(item),
                        );
                      },
                    ),
                  ],
                ),
              ),
            if (!_loading && _entries.isEmpty && (_controller.text.trim().isNotEmpty))
              Padding(
                padding: const EdgeInsets.only(top: 12.0),
                child: Text(
                  '没有找到匹配项',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
          ],
        ),
      ),
    );
  }
}