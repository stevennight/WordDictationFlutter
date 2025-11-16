import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import '../../../core/models/dictionary.dart';
import '../../../core/services/dictionary_service.dart';

class DictionarySettingsScreen extends StatefulWidget {
  const DictionarySettingsScreen({super.key});

  @override
  State<DictionarySettingsScreen> createState() => _DictionarySettingsScreenState();
}

class _DictionarySettingsScreenState extends State<DictionarySettingsScreen> {
  final DictionaryService _dictionaryService = DictionaryService();
  List<Dictionary> _dictionaries = [];

  @override
  void initState() {
    super.initState();
    _loadDictionaries();
  }

  Future<void> _loadDictionaries() async {
    final dictionaries = await _dictionaryService.getDictionaries();
    if (mounted) {
      setState(() {
        _dictionaries = dictionaries;
      });
    }
  }

  Future<void> _pickDictionaryFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mdx', 'mdd'],
    );

    if (result != null) {
      PlatformFile file = result.files.first;
      if (file.path != null) {
        final dictionary = Dictionary(name: p.basename(file.path!), path: file.path!);
        await _dictionaryService.addDictionary(dictionary);
        _loadDictionaries(); // Reload the list
      }
    }
  }

  Future<void> _removeDictionary(String path) async {
    await _dictionaryService.removeDictionary(path);
    _loadDictionaries(); // Reload the list
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('词典管理'),
      ),
      body: _dictionaries.isEmpty
          ? const Center(
              child: Text('还没有添加词典。'),
            )
          : ListView.builder(
              itemCount: _dictionaries.length,
              itemBuilder: (context, index) {
                final dictionary = _dictionaries[index];
                return ListTile(
                  leading: const Icon(Icons.menu_book),
                  title: Text(dictionary.name),
                  subtitle: Text(dictionary.path),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _removeDictionary(dictionary.path),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _pickDictionaryFile,
        child: const Icon(Icons.add),
      ),
    );
  }
}