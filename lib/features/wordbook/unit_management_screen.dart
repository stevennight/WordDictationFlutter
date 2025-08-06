import 'package:flutter/material.dart';
import '../../shared/models/wordbook.dart';
import '../../shared/models/word.dart';
import '../../shared/models/unit.dart';
import '../../core/services/wordbook_service.dart';
import '../../core/services/unit_service.dart';
import 'wordbook_import_screen.dart';

class UnitManagementScreen extends StatefulWidget {
  final Wordbook wordbook;

  const UnitManagementScreen({super.key, required this.wordbook});

  @override
  State<UnitManagementScreen> createState() => _UnitManagementScreenState();
}

class _UnitManagementScreenState extends State<UnitManagementScreen> {
  final WordbookService _wordbookService = WordbookService();
  final UnitService _unitService = UnitService();
  List<Unit> _units = [];
  Map<int, List<Word>> _unitWords = {};
  bool _isLoading = true;
  String _searchQuery = '';
  List<Unit> _filteredUnits = [];
  bool _hasDataChanged = false; // 标记数据是否已更改

  @override
  void initState() {
    super.initState();
    _loadUnits();
  }

  Future<void> _loadUnits() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final units = await _unitService.getUnitsByWordbookId(widget.wordbook.id!);
      final Map<int, List<Word>> unitWords = {};
      
      for (final unit in units) {
        final words = await _wordbookService.getWordbookWords(widget.wordbook.id!);
        final unitWordsList = words.where((word) => word.unitId == unit.id).toList();
        unitWords[unit.id!] = unitWordsList;
      }

      setState(() {
        _units = units;
        _unitWords = unitWords;
        _isLoading = false;
      });
      
      _filterUnits();
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载单元失败: $e')),
        );
      }
    }
  }



  void _filterUnits() {
    if (_searchQuery.isEmpty) {
      _filteredUnits = List.from(_units);
    } else {
      _filteredUnits = _units
          .where((unit) => unit.name.toLowerCase().contains(_searchQuery.toLowerCase()))
          .toList();
    }
    
    // Sort units alphabetically
    _filteredUnits.sort((a, b) => a.name.compareTo(b.name));
  }

  void _showAddUnitDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加单元'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('选择添加单元的方式：'),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _importUnitFromFile();
                    },
                    icon: const Icon(Icons.file_upload),
                    label: const Text('导入文件'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _showCreateEmptyUnitDialog();
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('创建空单元'),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  void _showCreateEmptyUnitDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('创建空单元'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: '单元名称',
                hintText: '例如：第一单元、Unit 1等',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              final unitName = controller.text.trim();
              if (unitName.isNotEmpty) {
                Navigator.pop(context);
                _addEmptyUnit(unitName);
              }
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }

  Future<void> _importUnitFromFile() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => WordbookImportScreen(
          wordbook: widget.wordbook,
          isUnitMode: true,
        ),
      ),
    );
    
    if (result == true) {
      _hasDataChanged = true;
      _loadUnits();
    }
  }

  Future<void> _addEmptyUnit(String unitName) async {
    try {
      // Check if unit already exists
      final existingUnits = await _unitService.getUnitsByWordbookId(widget.wordbook.id!);
      if (existingUnits.any((unit) => unit.name == unitName)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('单元名称已存在')),
        );
        return;
      }

      final now = DateTime.now();
      final unit = Unit(
        name: unitName,
        wordbookId: widget.wordbook.id!,
        wordCount: 0,
        isLearned: false,
        createdAt: now,
        updatedAt: now,
      );

      await _unitService.createUnit(unit);
      _hasDataChanged = true;
      await _loadUnits();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已创建空单元：$unitName')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('创建单元失败: $e')),
      );
    }
  }

  Future<void> _editUnitName(Unit unit) async {
    final controller = TextEditingController(text: unit.name);
    
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('编辑单元名称'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '单元名称',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final newName = controller.text.trim();
              if (newName.isNotEmpty && newName != unit.name) {
                Navigator.of(context).pop(newName);
              } else {
                Navigator.of(context).pop();
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (result != null) {
      await _updateUnitName(unit, result);
    }
  }

  Future<void> _editUnitDescription(Unit unit) async {
    final controller = TextEditingController(text: unit.description ?? '');
    
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('编辑单元描述'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '单元描述（可选）',
            border: OutlineInputBorder(),
            hintText: '请输入单元描述',
          ),
          maxLines: 3,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final newDescription = controller.text.trim();
              Navigator.of(context).pop(newDescription.isEmpty ? null : newDescription);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (result != null || result == null) {
      await _updateUnitDescription(unit, result);
    }
  }

  Future<void> _updateUnitName(Unit unit, String newName) async {
    try {
      final updatedUnit = unit.copyWith(
        name: newName,
        updatedAt: DateTime.now(),
      );
      
      await _unitService.updateUnit(updatedUnit);
      await _loadUnits();
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('单元名称已更新为：$newName')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('更新单元名称失败: $e')),
      );
    }
  }

  Future<void> _updateUnitDescription(Unit unit, String? newDescription) async {
    try {
      final updatedUnit = unit.copyWith(
        description: newDescription,
        updatedAt: DateTime.now(),
      );
      
      await _unitService.updateUnit(updatedUnit);
      await _loadUnits();
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(newDescription?.isEmpty == false ? '单元描述已更新' : '单元描述已清空')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('更新单元描述失败: $e')),
      );
    }
  }

  Future<void> _deleteUnit(Unit unit) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除单元'),
        content: Text('确定要删除单元"${unit.name}"及其所有单词吗？此操作不可撤销。'),
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
        await _unitService.deleteUnit(unit.id!);
        await _wordbookService.updateWordbookWordCount(widget.wordbook.id!);
        _hasDataChanged = true;
        await _loadUnits();
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已删除单元：${unit.name}')),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败: $e')),
        );
      }
    }
  }

  Future<void> _toggleUnitLearned(Unit unit) async {
    try {
      await _unitService.toggleUnitLearnedStatus(unit.id!);
      await _loadUnits();
      
      final status = unit.isLearned ? '未学完' : '已学完';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('单元"${unit.name}"已标记为$status')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('更新学习状态失败: $e')),
      );
    }
  }

  void _showUnitWords(Unit unit) {
    final words = _unitWords[unit.id!] ?? [];
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: false,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 8, bottom: 8),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${unit.name} (${words.length} 个单词)',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  ),
                ],
              ),
            ),
            
            const Divider(height: 1),
            
            // Words list
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: words.length,
                itemBuilder: (context, index) {
                  final word = words[index];
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
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(word.answer),
                          if (word.partOfSpeech != null || word.level != null)
                            const SizedBox(height: 4),
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
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.wordbook.name} - 单元管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _showAddUnitDialog,
            tooltip: '添加新单元',
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
                Text(
                  '单元管理',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '管理词书中的单元，每个单元可以包含不同主题的单词',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.folder,
                      size: 16,
                      color: Colors.grey[600],
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${_unitWords.length} 个单元',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Icon(
                      Icons.book,
                      size: 16,
                      color: Colors.grey[600],
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${_unitWords.values.fold(0, (sum, words) => sum + words.length)} 个单词',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          // Search bar
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              decoration: const InputDecoration(
                hintText: '搜索单元...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                  _filterUnits();
                });
              },
            ),
          ),
          
          // Units list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredUnits.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _searchQuery.isEmpty ? Icons.folder_outlined : Icons.search_off,
                              size: 64,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _searchQuery.isEmpty ? '还没有单元' : '没有找到匹配的单元',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _searchQuery.isEmpty ? '点击右上角的 + 按钮添加新单元' : '尝试其他搜索关键词',
                              style: TextStyle(
                                color: Colors.grey[500],
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _filteredUnits.length,
                        itemBuilder: (context, index) {
                          final unit = _filteredUnits[index];
                          final words = _unitWords[unit.id!] ?? [];
                          
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: unit.isLearned ? Colors.green : Theme.of(context).primaryColor,
                                child: Icon(
                                  unit.isLearned ? Icons.check : Icons.folder,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                              title: Text(
                                unit.name,
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${words.length} 个单词',
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 12,
                                    ),
                                  ),
                                  if (unit.description != null && unit.description!.isNotEmpty)
                                    Text(
                                      unit.description!,
                                      style: TextStyle(
                                        color: Colors.grey[500],
                                        fontSize: 11,
                                        fontStyle: FontStyle.italic,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  if (unit.isLearned)
                                    Text(
                                      '已学完',
                                      style: TextStyle(
                                        color: Colors.green[600],
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                ],
                              ),
                              trailing: PopupMenuButton<String>(
                                onSelected: (value) {
                                  switch (value) {
                                    case 'view':
                                      _showUnitWords(unit);
                                      break;
                                    case 'edit_name':
                                      _editUnitName(unit);
                                      break;
                                    case 'edit_description':
                                      _editUnitDescription(unit);
                                      break;
                                    case 'toggle_learned':
                                      _toggleUnitLearned(unit);
                                      break;
                                    case 'delete':
                                      _deleteUnit(unit);
                                      break;
                                  }
                                },
                                itemBuilder: (context) => [
                                  const PopupMenuItem(
                                    value: 'view',
                                    child: ListTile(
                                      leading: Icon(Icons.visibility),
                                      title: Text('查看单词'),
                                      contentPadding: EdgeInsets.zero,
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'edit_name',
                                    child: ListTile(
                                      leading: Icon(Icons.edit),
                                      title: Text('编辑名称'),
                                      contentPadding: EdgeInsets.zero,
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'edit_description',
                                    child: ListTile(
                                      leading: Icon(Icons.description),
                                      title: Text('编辑描述'),
                                      contentPadding: EdgeInsets.zero,
                                    ),
                                  ),
                                  const PopupMenuDivider(),
                                  PopupMenuItem(
                                    value: 'toggle_learned',
                                    child: ListTile(
                                      leading: Icon(unit.isLearned ? Icons.refresh : Icons.check),
                                      title: Text(unit.isLearned ? '标记为未学完' : '标记为已学完'),
                                      contentPadding: EdgeInsets.zero,
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: ListTile(
                                      leading: Icon(Icons.delete, color: Colors.red),
                                      title: Text('删除单元', style: TextStyle(color: Colors.red)),
                                      contentPadding: EdgeInsets.zero,
                                    ),
                                  ),
                                ],
                              ),
                              onTap: () => _showUnitWords(unit),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddUnitDialog,
        icon: const Icon(Icons.add),
        label: const Text('添加单元'),
      ),
    );
  }

  @override
  void dispose() {
    // 在页面关闭时返回数据变更状态
    if (_hasDataChanged) {
      Navigator.of(context).pop(true);
    }
    super.dispose();
  }
}