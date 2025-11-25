import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'dart:io';
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
    try {
      FilePickerResult? result;
      if (Platform.isAndroid) {
        result = await FilePicker.platform.pickFiles(
          type: FileType.any,
          allowMultiple: false,
          withData: false,
        );
      } else {
        result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['mdx', 'mdd'],
          allowMultiple: false,
          withData: true,
        );
      }

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        final ext = (file.extension ?? p.extension(file.name).replaceFirst('.', '')).toLowerCase();
        if (ext != 'mdx' && ext != 'mdd') {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('仅支持 .mdx/.mdd 文件')),
          );
          return;
        }

        String finalPath;
        if (file.path != null) {
          finalPath = file.path!;
        } else if ((file as dynamic).readStream != null) {
          final appDir = await getApplicationDocumentsDirectory();
          final dictDir = Directory(p.join(appDir.path, 'dictionaries'));
          if (!await dictDir.exists()) {
            await dictDir.create(recursive: true);
          }
          final outPath = p.join(dictDir.path, file.name);
          final sink = File(outPath).openWrite();
          await ((file as dynamic).readStream as Stream<List<int>>).pipe(sink);
          await sink.flush();
          await sink.close();
          finalPath = outPath;
        } else if (file.bytes != null) {
          final appDir = await getApplicationDocumentsDirectory();
          final dictDir = Directory(p.join(appDir.path, 'dictionaries'));
          if (!await dictDir.exists()) {
            await dictDir.create(recursive: true);
          }
          final outPath = p.join(dictDir.path, file.name);
          await File(outPath).writeAsBytes(file.bytes!);
          finalPath = outPath;
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('无法获取所选文件路径，请将文件放在可访问目录（如“下载”）后重试')),
          );
          return;
        }

        final dictionary = Dictionary(name: p.basename(finalPath), path: finalPath);
        await _dictionaryService.addDictionary(dictionary);
        await _loadDictionaries();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已添加词典: ${p.basename(finalPath)}')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('选择文件失败: $e')),
      );
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
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Text(
                          '参与AI释义',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ),
                      Switch(
                        value: dictionary.enabledForAI,
                        onChanged: (v) async {
                          await _dictionaryService.setDictionaryEnabled(dictionary.path, v);
                          await _loadDictionaries();
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _removeDictionary(dictionary.path),
                      ),
                    ],
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