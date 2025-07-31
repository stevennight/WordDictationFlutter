import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../shared/widgets/handwriting_canvas.dart';
import '../../../shared/providers/theme_provider.dart';
import '../../../shared/enums/pen_mode.dart';

class DictationToolbar extends StatefulWidget {
  final GlobalKey<State<HandwritingCanvas>> canvasKey;
  final VoidCallback onClear;
  final VoidCallback onUndo;

  const DictationToolbar({
    super.key,
    required this.canvasKey,
    required this.onClear,
    required this.onUndo,
  });

  @override
  State<DictationToolbar> createState() => _DictationToolbarState();
}

class _DictationToolbarState extends State<DictationToolbar> {
  PenMode _currentMode = PenMode.pen;
  double _penSize = 3.0;
  Color _penColor = Colors.black;
  double _eraserSize = 10.0;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Mode and action buttons
          Row(
            children: [
              // Pen mode button
              _buildModeButton(
                icon: Icons.edit,
                label: '画笔',
                mode: PenMode.pen,
                isSelected: _currentMode == PenMode.pen,
                onTap: () => _setMode(PenMode.pen),
              ),
              const SizedBox(width: 8),
              
              // Eraser mode button
              _buildModeButton(
                icon: Icons.auto_fix_high,
                label: '橡皮',
                mode: PenMode.eraser,
                isSelected: _currentMode == PenMode.eraser,
                onTap: () => _setMode(PenMode.eraser),
              ),
              
              const Spacer(),
              
              // Undo button
              IconButton(
                onPressed: widget.onUndo,
                icon: const Icon(Icons.undo),
                tooltip: '撤销',
                style: IconButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.surface,
                ),
              ),
              const SizedBox(width: 8),
              
              // Clear button
              IconButton(
                onPressed: () => _showClearConfirmation(),
                icon: const Icon(Icons.clear_all),
                tooltip: '清空',
                style: IconButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.surface,
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 8),
          
          // Size and color controls
          Row(
            children: [
              // Size control
              Expanded(
                flex: 3,
                child: _buildSizeControl(),
              ),
              
              const SizedBox(width: 16),
              
              // Color control (only for pen mode)
              if (_currentMode == PenMode.pen)
                Expanded(
                  flex: 2,
                  child: _buildColorControl(),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildModeButton({
    required IconData icon,
    required String label,
    required PenMode mode,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outline,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected
                  ? Theme.of(context).colorScheme.onPrimary
                  : Theme.of(context).colorScheme.onSurface,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected
                    ? Theme.of(context).colorScheme.onPrimary
                    : Theme.of(context).colorScheme.onSurface,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSizeControl() {
    final currentSize = _currentMode == PenMode.pen ? _penSize : _eraserSize;
    final maxSize = _currentMode == PenMode.pen ? 10.0 : 20.0;
    final minSize = _currentMode == PenMode.pen ? 1.0 : 5.0;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${_currentMode == PenMode.pen ? '画笔' : '橡皮'}大小: ${currentSize.toInt()}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Slider(
                value: currentSize,
                min: minSize,
                max: maxSize,
                divisions: (maxSize - minSize).toInt(),
                onChanged: (value) {
                  setState(() {
                    if (_currentMode == PenMode.pen) {
                      _penSize = value;
                    } else {
                      _eraserSize = value;
                    }
                  });
                  _updateCanvasSettings();
                },
              ),
            ),
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: _currentMode == PenMode.pen ? _penColor : Colors.grey,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
              child: Center(
                child: Container(
                  width: currentSize,
                  height: currentSize,
                  decoration: BoxDecoration(
                    color: _currentMode == PenMode.pen 
                        ? _penColor 
                        : Theme.of(context).colorScheme.surface,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildColorControl() {
    final colors = [
      Colors.black,
      Colors.blue,
      Colors.red,
      Colors.green,
      Colors.purple,
      Colors.orange,
    ];
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '画笔颜色',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 4,
          children: colors.map((color) {
            final isSelected = _penColor == color;
            return GestureDetector(
              onTap: () {
                setState(() {
                  _penColor = color;
                });
                _updateCanvasSettings();
              },
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.outline,
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: isSelected
                    ? Icon(
                        Icons.check,
                        size: 16,
                        color: color == Colors.black || color == Colors.blue
                            ? Colors.white
                            : Colors.black,
                      )
                    : null,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  void _setMode(PenMode mode) {
    setState(() {
      _currentMode = mode;
    });
    _updateCanvasSettings();
  }

  void _updateCanvasSettings() {
    final canvas = widget.canvasKey.currentState as dynamic;
    if (canvas != null) {
      canvas.setPenMode(_currentMode);
      if (_currentMode == PenMode.pen) {
        canvas.setStrokeWidth(_penSize);
        canvas.setStrokeColor(_penColor);
      } else {
        canvas.setStrokeWidth(_eraserSize);
      }
    }
  }

  void _showClearConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认清空'),
        content: const Text('确定要清空画布吗？此操作无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              widget.onClear();
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}