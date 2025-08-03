import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/dictation_provider.dart';
import 'handwriting_canvas.dart';
import '../../core/services/config_service.dart';

class UnifiedCanvasToolbar extends StatefulWidget {
  final GlobalKey<State<HandwritingCanvas>> canvasKey;
  final VoidCallback? onClear;
  final VoidCallback? onUndo;
  final bool isDictationMode; // 是否为默写模式
  final bool showDictationControls; // 是否显示默写特有的控制按钮
  
  const UnifiedCanvasToolbar({
    super.key,
    required this.canvasKey,
    this.onClear,
    this.onUndo,
    this.isDictationMode = false,
    this.showDictationControls = false,
  });

  @override
  State<UnifiedCanvasToolbar> createState() => _UnifiedCanvasToolbarState();
}

class _UnifiedCanvasToolbarState extends State<UnifiedCanvasToolbar> {
  bool _isEraserMode = false;
  double _strokeWidth = 3.0;
  Color _penColor = Colors.black;

  @override
  void initState() {
    super.initState();
    _loadDefaultBrushSize();
  }

  Future<void> _loadDefaultBrushSize() async {
    try {
      final configService = await ConfigService.getInstance();
      final defaultSize = (await configService.getSetting('default_brush_size'))?.toDouble() ?? 3.0;
      if (mounted) {
        setState(() {
          _strokeWidth = defaultSize;
        });
        _updateCanvasSettings();
      }
    } catch (e) {
      // Use default value if loading fails
      print('Failed to load default brush size: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DictationProvider>(
      builder: (context, dictationProvider, child) {
        // 根据批改模式设置固定颜色（仅在默写模式下）
        if (widget.isDictationMode) {
          final isAnnotationMode = dictationProvider.isAnnotationMode;
          final newPenColor = isAnnotationMode ? Colors.red : Colors.black;
          
          // 如果颜色发生变化，更新画笔颜色
          if (_penColor != newPenColor) {
            _penColor = newPenColor;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _updateCanvasSettings();
            });
          }
        }
        
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceVariant,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
          ),
          child: Row(
            children: [
              // 画笔/橡皮切换
              Column(
                children: [
                  IconButton(
                    onPressed: () {
                      setState(() {
                        _isEraserMode = !_isEraserMode;
                      });
                      _updateCanvasSettings();
                    },
                    icon: Icon(
                      _isEraserMode ? Icons.auto_fix_normal : Icons.brush,
                      color: _isEraserMode ? Colors.red : Colors.blue,
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor: _isEraserMode 
                          ? Colors.red.withOpacity(0.1) 
                          : Colors.blue.withOpacity(0.1),
                    ),
                  ),
                  Text(
                    _isEraserMode ? '橡皮' : '画笔',
                    style: TextStyle(
                      fontSize: 12,
                      color: _isEraserMode ? Colors.red : Colors.blue,
                    ),
                  ),
                ],
              ),
              
              const SizedBox(width: 8),
              
              // 撤销按钮
              Column(
                children: [
                  IconButton(
                    onPressed: () {
                      final canvas = widget.canvasKey.currentState as dynamic;
                      if (canvas != null) {
                        canvas.undo();
                      }
                      widget.onUndo?.call();
                    },
                    icon: const Icon(Icons.undo),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.grey.withOpacity(0.1),
                    ),
                  ),
                  const Text(
                    '撤销',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
              
              const SizedBox(width: 8),
              
              // 清空按钮
              Column(
                children: [
                  IconButton(
                    onPressed: () {
                      _showClearConfirmation();
                    },
                    icon: const Icon(Icons.clear),
                    tooltip: '清空画板',
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.grey.withOpacity(0.1),
                    ),
                  ),
                  const Text(
                    '清空',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
              
              const SizedBox(width: 16),
              
              // 画笔大小控制
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '大小：${_strokeWidth.toInt()}', 
                      style: const TextStyle(
                        fontWeight: FontWeight.w500, 
                        fontSize: 12
                      ),
                    ),
                    Slider(
                      value: _strokeWidth,
                      min: 1.0,
                      max: 10.0,
                      divisions: 9,
                      onChanged: (value) {
                        setState(() {
                          _strokeWidth = value;
                        });
                        _updateCanvasSettings();
                      },
                    ),
                  ],
                ),
              ),
              
              const SizedBox(width: 16),
              
              // 颜色控制（默写模式下隐藏）
              if (!widget.isDictationMode)
                Expanded(
                  flex: 3,
                  child: _buildColorControl(),
                ),
            ],
          ),
        );
      },
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
        const Text(
           '颜色',
           style: TextStyle(
             fontWeight: FontWeight.w500,
             fontSize: 12,
           ),
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

  void _updateCanvasSettings() {
    final canvas = widget.canvasKey.currentState as dynamic;
    if (canvas != null) {
      if (_isEraserMode) {
        canvas.setDrawingMode(DrawingMode.eraser);
        canvas.setStrokeWidth(_strokeWidth * 2); // 橡皮擦稍大一些
      } else {
        canvas.setDrawingMode(DrawingMode.pen);
        canvas.setStrokeColor(_penColor);
        canvas.setStrokeWidth(_strokeWidth);
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
                final canvas = widget.canvasKey.currentState as dynamic;
                if (canvas != null) {
                  canvas.clearCanvas();
                }
                widget.onClear?.call();
              },
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
  }


}