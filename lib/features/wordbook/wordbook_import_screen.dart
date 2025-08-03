import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../shared/models/word.dart';
import '../../shared/models/wordbook.dart';
import '../../core/services/wordbook_service.dart';
import '../../core/services/word_import_service.dart';

class WordbookImportScreen extends StatefulWidget {
  final Wordbook? wordbook;
  final bool isUnitMode;
  
  const WordbookImportScreen({
    super.key,
    this.wordbook,
    this.isUnitMode = false,
  });

  @override
  State<WordbookImportScreen> createState() => _WordbookImportScreenState();
}

class _WordbookImportScreenState extends State<WordbookImportScreen> {
  final WordbookService _wordbookService = WordbookService();
  final WordImportService _wordImportService = WordImportService();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _unitNameController = TextEditingController();
  
  List<Word> _importedWords = [];
  bool _isImporting = false;
  bool _isSaving = false;
  String? _selectedFileName;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickAndImportFile() async {
    try {
      setState(() {
        _isImporting = true;
      });

      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'docx', 'csv'],
      );

      if (result != null) {
        PlatformFile file = result.files.first;
        _selectedFileName = file.name;
        
        // Auto-fill name from filename if empty
        if (widget.isUnitMode) {
          if (_unitNameController.text.isEmpty) {
            final nameWithoutExtension = file.name.split('.').first;
            _unitNameController.text = nameWithoutExtension;
          }
        } else {
          if (_nameController.text.isEmpty) {
            final nameWithoutExtension = file.name.split('.').first;
            _nameController.text = nameWithoutExtension;
          }
        }

        List<Word> words;
        if (file.extension?.toLowerCase() == 'xlsx') {
          words = await _wordImportService.importFromExcel(file.path!);
        } else if (file.extension?.toLowerCase() == 'docx') {
          words = await _wordImportService.importFromDocx(file.path!);
        } else if (file.extension?.toLowerCase() == 'csv') {
          words = await _wordImportService.importFromCsv(file.path!);
        } else {
          throw Exception('不支持的文件格式');
        }

        setState(() {
          _importedWords = words;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('成功导入 ${words.length} 个单词')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入失败: $e')),
        );
      }
    } finally {
      setState(() {
        _isImporting = false;
      });
    }
  }

  Future<void> _saveWordbook() async {
    if (widget.isUnitMode) {
      await _saveToExistingWordbook();
    } else {
      await _saveAsNewWordbook();
    }
  }

  Future<void> _saveAsNewWordbook() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入词书名称')),
      );
      return;
    }

    if (_importedWords.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先导入单词')),
      );
      return;
    }

    try {
      setState(() {
        _isSaving = true;
      });

      await _wordbookService.importWordsToWordbook(
        name: name,
        words: _importedWords,
        description: _descriptionController.text.trim().isEmpty 
            ? null 
            : _descriptionController.text.trim(),
        originalFileName: _selectedFileName,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('词书「$name」创建成功')),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
      }
    } finally {
      setState(() {
        _isSaving = false;
      });
    }
  }

  Future<void> _saveToExistingWordbook() async {
    final unitName = _unitNameController.text.trim();
    if (unitName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入单元名称')),
      );
      return;
    }

    if (_importedWords.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先导入单词')),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final now = DateTime.now();
      
      // 为单词设置单元名称和词书ID
      final wordsWithUnit = _importedWords.map((word) => word.copyWith(
        category: unitName,
        wordbookId: widget.wordbook!.id!,
        createdAt: now,
        updatedAt: now,
      )).toList();

      // 保存单词到数据库
      for (final word in wordsWithUnit) {
        await _wordbookService.addWordToWordbook(word);
      }

      // 更新词书的单词数量
      await _wordbookService.updateWordbookWordCount(widget.wordbook!.id!);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('成功添加 ${_importedWords.length} 个单词到单元"$unitName"')),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
      }
    } finally {
      setState(() {
        _isSaving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isUnitMode ? '导入单元' : '导入词书'),
        actions: [
          if (_importedWords.isNotEmpty && !_isSaving)
            TextButton(
              onPressed: _saveWordbook,
              child: const Text('保存'),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // File import section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '1. 选择文件',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '支持 .xlsx、.docx 和 .csv 格式的文件\nExcel格式：单词 | 词性 | 中文 | 等级',
                      style: TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isImporting ? null : _pickAndImportFile,
                        icon: _isImporting 
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.file_upload),
                        label: Text(_isImporting ? '导入中...' : '选择文件'),
                      ),
                    ),
                    if (_selectedFileName != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        '已选择: $_selectedFileName',
                        style: const TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Wordbook info section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.isUnitMode ? '2. 单元信息' : '2. 词书信息',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (widget.isUnitMode) ...[
                       if (widget.wordbook != null)
                         Card(
                           child: Padding(
                             padding: const EdgeInsets.all(16),
                             child: Column(
                               crossAxisAlignment: CrossAxisAlignment.start,
                               children: [
                                 Text(
                                   '目标词书: ${widget.wordbook!.name}',
                                   style: Theme.of(context).textTheme.titleMedium,
                                 ),
                                 if (widget.wordbook!.description?.isNotEmpty == true)
                                   Text(
                                     widget.wordbook!.description!,
                                     style: Theme.of(context).textTheme.bodyMedium,
                                   ),
                               ],
                             ),
                           ),
                         ),
                       const SizedBox(height: 16),
                       TextField(
                         controller: _unitNameController,
                         decoration: const InputDecoration(
                           labelText: '单元名称 *',
                           border: OutlineInputBorder(),
                           hintText: '例如：第一单元、Unit 1等',
                         ),
                       ),
                     ],
                    if (!widget.isUnitMode) ...[
                       TextField(
                         controller: _nameController,
                         decoration: const InputDecoration(
                           labelText: '词书名称 *',
                           border: OutlineInputBorder(),
                           hintText: '请输入词书名称',
                         ),
                       ),
                       const SizedBox(height: 16),
                       TextField(
                         controller: _descriptionController,
                         decoration: const InputDecoration(
                           labelText: '描述（可选）',
                           border: OutlineInputBorder(),
                           hintText: '请输入词书描述',
                         ),
                         maxLines: 3,
                       ),
                     ],
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Preview section
            if (_importedWords.isNotEmpty) ...[
              Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '3. 预览 (${_importedWords.length} 个单词)',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            '前5个单词预览:',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      height: 300, // 固定高度
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        itemCount: _importedWords.length > 5 ? 5 : _importedWords.length,
                         itemBuilder: (context, index) {
                           final word = _importedWords[index];
                           return ListTile(
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
                             subtitle: Column(
                               crossAxisAlignment: CrossAxisAlignment.start,
                               children: [
                                 Text(word.answer),
                                 if (word.partOfSpeech != null || word.level != null)
                                   Row(
                                     children: [
                                       if (word.partOfSpeech != null)
                                         Chip(
                                           label: Text(
                                             word.partOfSpeech!,
                                             style: const TextStyle(fontSize: 10),
                                           ),
                                           backgroundColor: Colors.blue[100],
                                           materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                         ),
                                       if (word.partOfSpeech != null && word.level != null)
                                         const SizedBox(width: 4),
                                       if (word.level != null)
                                         Chip(
                                           label: Text(
                                             word.level!,
                                             style: const TextStyle(fontSize: 10),
                                           ),
                                           backgroundColor: Colors.green[100],
                                           materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                         ),
                                     ],
                                   ),
                               ],
                             ),
                             trailing: word.category != null 
                                 ? Chip(
                                     label: Text(
                                       word.category!,
                                       style: const TextStyle(fontSize: 12),
                                     ),
                                     backgroundColor: Colors.grey[200],
                                   )
                                 : null,
                           );
                         },
                       ),
                     ),
                     if (_importedWords.length > 5)
                       Padding(
                         padding: const EdgeInsets.all(8.0),
                         child: Text(
                           '... 还有 ${_importedWords.length - 5} 个单词',
                           style: TextStyle(
                             color: Colors.grey[600],
                             fontStyle: FontStyle.italic,
                           ),
                           textAlign: TextAlign.center,
                         ),
                       ),
                   ],
                 ),
               ),
            ],
            
            // Save button
            if (_importedWords.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _saveWordbook,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _isSaving
                        ? const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                              SizedBox(width: 8),
                              Text('保存中...'),
                            ],
                          )
                        : Text(
                            widget.isUnitMode ? '保存单元' : '创建词书',
                            style: const TextStyle(fontSize: 16),
                          ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}