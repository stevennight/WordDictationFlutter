import 'package:flutter/material.dart';
import '../../../shared/models/dictation_session.dart';

class HomeDictationModeDialog extends StatefulWidget {
  final int totalWords;
  final DictationMode initialMode;

  const HomeDictationModeDialog({
    super.key,
    required this.totalWords,
    required this.initialMode,
  });

  @override
  State<HomeDictationModeDialog> createState() => _HomeDictationModeDialogState();
}

class _HomeDictationModeDialogState extends State<HomeDictationModeDialog> {
  int? _selectedMode; // 0: 译文->原文, 1: 原文->译文
  int _selectedQuantity = -1; // -1: 全部, 其他: 具体数量, 0: 自定义
  final TextEditingController _customController = TextEditingController();

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('选择默写设置'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '共 ${widget.totalWords} 个单词可用',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            
            // Quantity selection
            Text(
              '默写数量',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            
            _buildQuantityOptions(),
            
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
            final quantity = _getSelectedQuantity();
            Navigator.of(context).pop({
              'mode': _selectedMode!,
              'quantity': quantity,
            });
          } : null,
          child: const Text('开始默写'),
        ),
      ],
    );
  }

  bool _canStartDictation() {
    if (_selectedMode == null) return false;
    if (_selectedQuantity == 0) {
      // Custom quantity
      final customValue = int.tryParse(_customController.text);
      return customValue != null && customValue > 0 && customValue <= widget.totalWords;
    }
    return _selectedQuantity != 0;
  }

  int _getSelectedQuantity() {
    if (_selectedQuantity == 0) {
      return int.parse(_customController.text);
    }
    return _selectedQuantity;
  }

  Widget _buildQuantityOptions() {
    return Column(
      children: [
        // All words
        _buildQuantityOption(
          title: '全部单词',
          subtitle: '${widget.totalWords} 个单词',
          value: -1,
          icon: Icons.select_all,
        ),
        
        const SizedBox(height: 8),
        
        // Quick options
        if (widget.totalWords >= 10)
          _buildQuantityOption(
            title: '10 个单词',
            subtitle: '快速练习',
            value: 10,
            icon: Icons.speed,
          ),
        
        if (widget.totalWords >= 20)
          const SizedBox(height: 8),
        
        if (widget.totalWords >= 20)
          _buildQuantityOption(
            title: '20 个单词',
            subtitle: '标准练习',
            value: 20,
            icon: Icons.fitness_center,
          ),
        
        if (widget.totalWords >= 50)
          const SizedBox(height: 8),
        
        if (widget.totalWords >= 50)
          _buildQuantityOption(
            title: '50 个单词',
            subtitle: '强化练习',
            value: 50,
            icon: Icons.trending_up,
          ),
        
        const SizedBox(height: 8),
        
        // Custom quantity
        _buildCustomQuantityOption(),
      ],
    );
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.edit,
                    color: isSelected
                        ? Theme.of(context).colorScheme.onPrimaryContainer
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '自定义数量',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: isSelected
                            ? Theme.of(context).colorScheme.onPrimaryContainer
                            : null,
                        fontWeight: isSelected ? FontWeight.bold : null,
                      ),
                    ),
                  ),
                  if (isSelected)
                    Icon(
                      Icons.check_circle,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                ],
              ),
              if (isSelected) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _customController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    hintText: '输入数量 (1-${widget.totalWords})',
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (value) {
                    setState(() {}); // Trigger rebuild to update button state
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
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
}