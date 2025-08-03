import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class WordbookQuantitySelectionDialog extends StatefulWidget {
  final int totalWords;
  final String? unitName;

  const WordbookQuantitySelectionDialog({
    super.key,
    required this.totalWords,
    this.unitName,
  });

  @override
  State<WordbookQuantitySelectionDialog> createState() => _WordbookQuantitySelectionDialogState();
}

class _WordbookQuantitySelectionDialogState extends State<WordbookQuantitySelectionDialog> {
  int _selectedQuantity = -1; // -1 for all, 0 for custom, positive for preset
  final TextEditingController _customController = TextEditingController();
  final List<int> _presetQuantities = [10, 20, 30, 50];

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.unitName != null ? '选择默写数量 - ${widget.unitName}' : '选择默写数量'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '总共 ${widget.totalWords} 个单词',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            
            // All words option
            _buildQuantityOption(
              title: '全部单词',
              subtitle: '${widget.totalWords} 个',
              value: -1,
              icon: Icons.select_all,
            ),
            
            const SizedBox(height: 8),
            
            // Preset quantities
            ...(_presetQuantities
                .where((quantity) => quantity <= widget.totalWords)
                .map((quantity) => _buildQuantityOption(
                      title: '$quantity 个单词',
                      subtitle: '预设数量',
                      value: quantity,
                      icon: Icons.format_list_numbered,
                    ))),
            
            const SizedBox(height: 8),
            
            // Custom quantity
            _buildCustomQuantityOption(),
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
            int quantity = _selectedQuantity;
            if (_selectedQuantity == 0) {
              // Custom quantity
              final customValue = int.tryParse(_customController.text);
              if (customValue != null && customValue > 0 && customValue <= widget.totalWords) {
                quantity = customValue;
              } else {
                return;
              }
            }
            Navigator.of(context).pop(quantity);
          } : null,
          child: const Text('下一步'),
        ),
      ],
    );
  }

  bool _canStartDictation() {
    if (_selectedQuantity == 0) {
      // Custom quantity
      final customValue = int.tryParse(_customController.text);
      return customValue != null && customValue > 0 && customValue <= widget.totalWords;
    }
    return _selectedQuantity != 0;
  }

  Widget _buildQuantityOption({
    required String title,
    required String subtitle,
    required int value,
    required IconData icon,
  }) {
    final isSelected = _selectedQuantity == value;
    
    return Card(
      elevation: isSelected ? 4 : 1,
      color: isSelected 
          ? Theme.of(context).colorScheme.primaryContainer
          : null,
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedQuantity = value;
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

  Widget _buildCustomQuantityOption() {
    final isSelected = _selectedQuantity == 0;
    
    return Card(
      elevation: isSelected ? 4 : 1,
      color: isSelected 
          ? Theme.of(context).colorScheme.primaryContainer
          : null,
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedQuantity = 0;
          });
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(
                Icons.edit,
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
                      '自定义数量',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: isSelected
                            ? Theme.of(context).colorScheme.onPrimaryContainer
                            : null,
                        fontWeight: isSelected ? FontWeight.bold : null,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 40,
                      child: TextField(
                        controller: _customController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: InputDecoration(
                          hintText: '输入数量 (1-${widget.totalWords})',
                          border: const OutlineInputBorder(),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          filled: true,
                          fillColor: isSelected
                              ? Theme.of(context).colorScheme.surface
                              : null,
                        ),
                        onTap: () {
                          setState(() {
                            _selectedQuantity = 0;
                          });
                        },
                        onChanged: (value) {
                          setState(() {
                            if (value.isNotEmpty) {
                              _selectedQuantity = 0;
                            }
                          });
                        },
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