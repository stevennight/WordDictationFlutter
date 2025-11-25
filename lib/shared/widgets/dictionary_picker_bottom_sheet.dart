import 'package:flutter/material.dart';
import '../../core/models/dictionary.dart';

class DictionaryPickerBottomSheet extends StatefulWidget {
  final List<Dictionary> allDictionaries;
  final List<String>? initialPaths;

  const DictionaryPickerBottomSheet({
    super.key,
    required this.allDictionaries,
    this.initialPaths,
  });

  @override
  State<DictionaryPickerBottomSheet> createState() => _DictionaryPickerBottomSheetState();
}

class _DictionaryPickerBottomSheetState extends State<DictionaryPickerBottomSheet> {
  late Set<String> selectedPaths;
  bool setAsDefault = false;

  @override
  void initState() {
    super.initState();
    selectedPaths = Set.from(widget.initialPaths ?? widget.allDictionaries.where((d) => d.enabledForAI).map((d) => d.path));
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.allDictionaries.length;
    final enabled = widget.allDictionaries.where((d) => d.enabledForAI).length;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (_, controller) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            // Handle bar
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Icon(Icons.source_outlined, size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '词典来源',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Text(
                    '已启用 $enabled/$total 个',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            // List
            Expanded(
              child: ListView.builder(
                controller: controller,
                itemCount: widget.allDictionaries.length,
                itemBuilder: (context, index) {
                  final dict = widget.allDictionaries[index];
                  final selected = selectedPaths.contains(dict.path);
                  return CheckboxListTile(
                    value: selected,
                    onChanged: (v) {
                      setState(() {
                        if (v == true) {
                          selectedPaths.add(dict.path);
                        } else {
                          selectedPaths.remove(dict.path);
                        }
                      });
                    },
                    title: Text(dict.name),
                    subtitle: Text(dict.path, maxLines: 1, overflow: TextOverflow.ellipsis),
                    secondary: const Icon(Icons.menu_book),
                  );
                },
              ),
            ),
            // Footer actions
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  CheckboxListTile(
                    value: setAsDefault,
                    onChanged: (v) => setState(() => setAsDefault = v ?? false),
                    title: const Text('设为默认'),
                    subtitle: const Text('保存选择为词典管理的默认开关'),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('取消'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: selectedPaths.isEmpty
                              ? null
                              : () => Navigator.of(context).pop((selectedPaths.toList(), setAsDefault)),
                          child: const Text('确定'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 便捷方法：弹出词典选择底部抽屉
/// 返回：(List<String> selectedPaths, bool setAsDefault) 或 null（取消）
Future<(List<String>, bool)?> showDictionaryPicker(
  BuildContext context, {
  required List<Dictionary> allDictionaries,
  List<String>? initialPaths,
}) async {
  final result = await showModalBottomSheet<(List<String>, bool)>(
    context: context,
    isScrollControlled: true,
    builder: (_) => DictionaryPickerBottomSheet(
      allDictionaries: allDictionaries,
      initialPaths: initialPaths,
    ),
  );
  return result;
}
