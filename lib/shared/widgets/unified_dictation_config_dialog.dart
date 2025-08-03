import 'package:flutter/material.dart';
import '../models/dictation_session.dart';

class UnifiedDictationConfigDialog extends StatefulWidget {
  final int totalWords;
  final String? sourceName;
  final bool showQuantitySelection;
  final DictationMode? initialMode;

  const UnifiedDictationConfigDialog({
    super.key,
    required this.totalWords,
    this.sourceName,
    this.showQuantitySelection = true,
    this.initialMode,
  });

  @override
  State<UnifiedDictationConfigDialog> createState() => _UnifiedDictationConfigDialogState();
}

class _UnifiedDictationConfigDialogState extends State<UnifiedDictationConfigDialog> {
  int? _selectedMode; // 0: 译文->原文, 1: 原文->译文
  int? _selectedOrder; // 0: 顺序, 1: 乱序
  int _selectedQuantity = -1; // -1: 全部, 其他: 具体数量, 0: 自定义
  final TextEditingController _customController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.initialMode != null) {
      _selectedOrder = widget.initialMode == DictationMode.sequential ? 0 : 1;
    }
  }

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.sourceName != null 
          ? '选择默写设置 - ${widget.sourceName}' 
          : '选择默写设置'),
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
            
            // Quantity selection (only show if enabled)
            if (widget.showQuantitySelection) ..._buildQuantitySection(),
            
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
              subtitle: '看译文，默写原文',
              value: 1,
              icon: Icons.translate,
            ),
            
            const SizedBox(height: 8),
            
            _buildModeOption(
              title: '原文 → 译文',
              subtitle: '看原文，默写译文',
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
            final quantity = widget.showQuantitySelection ? _getSelectedQuantity() : widget.totalWords;
            Navigator.of(context).pop({
              'mode': _selectedMode!,
              'order': _selectedOrder!,
              'quantity': quantity,
            });
          } : null,
          child: const Text('开始默写'),
        ),
      ],
    );
  }

  List<Widget> _buildQuantitySection() {
    return [
      Text(
        '默写数量',
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
        ),
      ),
      const SizedBox(height: 12),
      _buildQuantityOptions(),
      const SizedBox(height: 20),
    ];
  }

  Widget _buildQuantityOptions() {
    return Column(
      children: [
        _buildQuantityOption(
          title: '全部单词',
          subtitle: '默写所有 ${widget.totalWords} 个单词',
          value: -1,
          icon: Icons.select_all,
        ),
        const SizedBox(height: 8),
        _buildQuantityOption(
          title: '10个单词',
          subtitle: '快速练习',
          value: 10,
          icon: Icons.speed,
          enabled: widget.totalWords >= 10,
        ),
        const SizedBox(height: 8),
        _buildQuantityOption(
          title: '20个单词',
          subtitle: '标准练习',
          value: 20,
          icon: Icons.fitness_center,
          enabled: widget.totalWords >= 20,
        ),
        const SizedBox(height: 8),
        _buildQuantityOption(
          title: '50个单词',
          subtitle: '强化练习',
          value: 50,
          icon: Icons.trending_up,
          enabled: widget.totalWords >= 50,
        ),
        const SizedBox(height: 8),
        _buildCustomQuantityOption(),
      ],
    );
  }

  Widget _buildQuantityOption({
    required String title,
    required String subtitle,
    required int value,
    required IconData icon,
    bool enabled = true,
  }) {
    return Card(
      elevation: _selectedQuantity == value ? 2 : 0,
      color: _selectedQuantity == value
          ? Theme.of(context).colorScheme.primaryContainer
          : null,
      child: InkWell(
        onTap: enabled ? () {
          setState(() {
            _selectedQuantity = value;
          });
        } : null,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(
                icon,
                color: enabled
                    ? (_selectedQuantity == value
                        ? Theme.of(context).colorScheme.onPrimaryContainer
                        : Theme.of(context).colorScheme.primary)
                    : Theme.of(context).colorScheme.outline,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: enabled
                            ? (_selectedQuantity == value
                                ? Theme.of(context).colorScheme.onPrimaryContainer
                                : null)
                            : Theme.of(context).colorScheme.outline,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: enabled
                            ? (_selectedQuantity == value
                                ? Theme.of(context).colorScheme.onPrimaryContainer
                                : Theme.of(context).colorScheme.onSurfaceVariant)
                            : Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
              if (_selectedQuantity == value)
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
    return Card(
      elevation: _selectedQuantity == 0 ? 2 : 0,
      color: _selectedQuantity == 0
          ? Theme.of(context).colorScheme.primaryContainer
          : null,
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedQuantity = 0;
          });
        },
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(
                Icons.edit,
                color: _selectedQuantity == 0
                    ? Theme.of(context).colorScheme.onPrimaryContainer
                    : Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '自定义数量',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: _selectedQuantity == 0
                            ? Theme.of(context).colorScheme.onPrimaryContainer
                            : null,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_selectedQuantity == 0)
                      SizedBox(
                        width: 120,
                        child: TextField(
                          controller: _customController,
                          keyboardType: TextInputType.number,
                          onChanged: (value) {
                            setState(() {
                              // 触发状态更新以重新计算按钮状态
                            });
                          },
                          decoration: InputDecoration(
                            hintText: '输入数量',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                          ),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (_selectedQuantity == 0)
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

  Widget _buildModeOption({
    required String title,
    required String subtitle,
    required int value,
    required IconData icon,
  }) {
    return Card(
      elevation: _selectedMode == value ? 2 : 0,
      color: _selectedMode == value
          ? Theme.of(context).colorScheme.primaryContainer
          : null,
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedMode = value;
          });
        },
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(
                icon,
                color: _selectedMode == value
                    ? Theme.of(context).colorScheme.onPrimaryContainer
                    : Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: _selectedMode == value
                            ? Theme.of(context).colorScheme.onPrimaryContainer
                            : null,
                      ),
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _selectedMode == value
                              ? Theme.of(context).colorScheme.onPrimaryContainer
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              if (_selectedMode == value)
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
    return Card(
      elevation: _selectedOrder == value ? 2 : 0,
      color: _selectedOrder == value
          ? Theme.of(context).colorScheme.primaryContainer
          : null,
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedOrder = value;
          });
        },
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(
                icon,
                color: _selectedOrder == value
                    ? Theme.of(context).colorScheme.onPrimaryContainer
                    : Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: _selectedOrder == value
                            ? Theme.of(context).colorScheme.onPrimaryContainer
                            : null,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: _selectedOrder == value
                            ? Theme.of(context).colorScheme.onPrimaryContainer
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (_selectedOrder == value)
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

  bool _canStartDictation() {
    if (_selectedMode == null || _selectedOrder == null) return false;
    if (!widget.showQuantitySelection) return true;
    
    if (_selectedQuantity == 0) {
      final customValue = int.tryParse(_customController.text);
      return customValue != null && customValue > 0 && customValue <= widget.totalWords;
    }
    
    return _selectedQuantity != -2; // -2 is unselected state
  }

  int _getSelectedQuantity() {
    if (_selectedQuantity == 0) {
      return int.tryParse(_customController.text) ?? 0;
    }
    return _selectedQuantity == -1 ? widget.totalWords : _selectedQuantity;
  }
}