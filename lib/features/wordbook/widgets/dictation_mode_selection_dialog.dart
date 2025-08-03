import 'package:flutter/material.dart';

class DictationModeSelectionDialog extends StatefulWidget {
  final int quantity;
  final String? unitName;

  const DictationModeSelectionDialog({
    super.key,
    required this.quantity,
    this.unitName,
  });

  @override
  State<DictationModeSelectionDialog> createState() => _DictationModeSelectionDialogState();
}

class _DictationModeSelectionDialogState extends State<DictationModeSelectionDialog> {
  int? _selectedMode; // 0: 译文->原文, 1: 原文->译文
  int? _selectedOrder; // 0: 顺序, 1: 乱序

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.unitName != null ? '选择默写模式 - ${widget.unitName}' : '选择默写模式'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '将默写 ${widget.quantity} 个单词',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            
            // Mode selection
            Text(
              '默写模式',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            
            _buildModeOption(
              title: '译文 → 原文',
              subtitle: '',
              value: 1,
              icon: Icons.translate,
            ),
            
            const SizedBox(height: 8),
            
            _buildModeOption(
              title: '原文 → 译文',
              subtitle: '',
              value: 0,
              icon: Icons.g_translate,
            ),
            
            const SizedBox(height: 20),
            
            // Order selection
            Text(
              '默写顺序',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            
            _buildOrderOption(
              title: '顺序模式',
              subtitle: '按照原始顺序进行默写',
              value: 0,
              icon: Icons.format_list_numbered,
            ),
            
            const SizedBox(height: 8),
            
            _buildOrderOption(
              title: '乱序模式',
              subtitle: '随机打乱顺序进行默写',
              value: 1,
              icon: Icons.shuffle,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: _canStartDictation() ? () {
            Navigator.of(context).pop({
              'mode': _selectedMode!,
              'order': _selectedOrder!,
            });
          } : null,
          child: const Text('开始默写'),
        ),
      ],
    );
  }

  bool _canStartDictation() {
    return _selectedMode != null && _selectedOrder != null;
  }

  Widget _buildModeOption({
    required String title,
    required String subtitle,
    required int value,
    required IconData icon,
  }) {
    final isSelected = _selectedMode == value;
    
    return Card(
      elevation: isSelected ? 4 : 1,
      color: isSelected 
          ? Theme.of(context).colorScheme.primaryContainer
          : null,
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedMode = value;
          });
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(
                icon,
                color: isSelected
                    ? Theme.of(context).colorScheme.onPrimaryContainer
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: isSelected
                            ? Theme.of(context).colorScheme.onPrimaryContainer
                            : null,
                        fontWeight: isSelected ? FontWeight.bold : null,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: isSelected
                            ? Theme.of(context).colorScheme.onPrimaryContainer
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                Icon(
                  Icons.check_circle,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOrderOption({
    required String title,
    required String subtitle,
    required int value,
    required IconData icon,
  }) {
    final isSelected = _selectedOrder == value;
    
    return Card(
      elevation: isSelected ? 4 : 1,
      color: isSelected 
          ? Theme.of(context).colorScheme.primaryContainer
          : null,
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedOrder = value;
          });
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(
                icon,
                color: isSelected
                    ? Theme.of(context).colorScheme.onPrimaryContainer
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: isSelected
                            ? Theme.of(context).colorScheme.onPrimaryContainer
                            : null,
                        fontWeight: isSelected ? FontWeight.bold : null,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: isSelected
                            ? Theme.of(context).colorScheme.onPrimaryContainer
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                Icon(
                  Icons.check_circle,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
            ],
          ),
        ),
      ),
    );
  }
}