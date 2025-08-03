import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../shared/widgets/handwriting_canvas.dart';
import '../../../shared/providers/theme_provider.dart';
import '../../../shared/providers/dictation_provider.dart';
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
    return Consumer<DictationProvider>(
      builder: (context, dictationProvider, child) {
        // 根据批改模式设置固定颜色
        final isAnnotationMode = dictationProvider.isAnnotationMode;
        final newPenColor = isAnnotationMode ? Colors.red : Colors.black;
        
        // 如果颜色发生变化，更新画笔颜色
        if (_penColor != newPenColor) {
          _penColor = newPenColor;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _updateCanvasSettings();
          });
        }
        
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
                  // 左侧：画笔大小控制
                  Expanded(
                    flex: 3,
                    child: _buildSizeControl(),
                  ),
                  
                  const SizedBox(width: 16),
                  
                  // 右侧：颜色选择器（默写模式和批改模式下隐藏）
                  Expanded(
                    flex: 2,
                    child: _buildColorControl(),
                  ),
                ],
              ),
            ],
          ),
        );
      },
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
    final dictationProvider = Provider.of<DictationProvider>(context, listen: false);
    final isAnnotationMode = dictationProvider.isAnnotationMode;
    final isDictationMode = !isAnnotationMode;
    
    // 在默写模式和批改模式下都隐藏颜色面板
    if (isDictationMode || isAnnotationMode) {
      return const SizedBox.shrink();
    }
    
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
    
    if (mode == PenMode.pen) {
      // 根据批改模式设置颜色
      final dictationProvider = Provider.of<DictationProvider>(context, listen: false);
      final isAnnotationMode = dictationProvider.isAnnotationMode;
      _penColor = isAnnotationMode ? Colors.red : Colors.black;
    }
    
    _updateCanvasSettings();
  }

  void _updateCanvasSettings() {
    final canvas = widget.canvasKey.currentState as dynamic;
    if (canvas != null) {
      if (_currentMode == PenMode.pen) {
        canvas.setDrawingMode(DrawingMode.pen);
        canvas.setStrokeColor(_penColor);
        canvas.setStrokeWidth(_penSize);
      } else {
        canvas.setDrawingMode(DrawingMode.eraser);
        canvas.setStrokeWidth(_eraserSize);
      }
    }
  }

  void _showClearConfirmation() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('确认清空'),
          content: const Text('确定要清空画布吗？此操作无法撤销。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                widget.onClear();
              },
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
  }
}