import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/dictation_provider.dart';
import 'handwriting_canvas.dart';
import '../../core/services/config_service.dart';

/// 可收起的画布工具栏组件
/// 默认收起状态，点击展开按钮可以展开显示完整工具栏
class CollapsibleCanvasToolbar extends StatefulWidget {
  final GlobalKey<State<HandwritingCanvas>> canvasKey;
  final VoidCallback? onClear;
  final VoidCallback? onUndo;
  final bool isDictationMode; // 是否为默写模式
  final bool showDictationControls; // 是否显示默写特有的控制按钮
  final VoidCallback? onBack; // 返回按钮回调
  final String? progressTitle; // 进度标题
  final int? currentProgress; // 当前进度
  final int? totalProgress; // 总进度
  
  const CollapsibleCanvasToolbar({
    super.key,
    required this.canvasKey,
    this.onClear,
    this.onUndo,
    this.isDictationMode = false,
    this.showDictationControls = false,
    this.onBack,
    this.progressTitle,
    this.currentProgress,
    this.totalProgress,
  });

  @override
  State<CollapsibleCanvasToolbar> createState() => _CollapsibleCanvasToolbarState();
}

class _CollapsibleCanvasToolbarState extends State<CollapsibleCanvasToolbar> {
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
      final defaultColorValue = (await configService.getSetting('default_brush_color'))?.toInt();
      final defaultColor = defaultColorValue != null ? Color(defaultColorValue) : Colors.black;
      
      if (mounted) {
        setState(() {
          _strokeWidth = defaultSize;
          // 只在非默写模式下加载颜色设置
          if (!widget.isDictationMode) {
            _penColor = defaultColor;
          }
        });
        _updateCanvasSettings();
      }
    } catch (e) {
      // Use default value if loading fails
      print('Failed to load default brush settings: $e');
    }
  }

  Future<void> _saveBrushSize(double size) async {
    try {
      final configService = await ConfigService.getInstance();
      await configService.setSetting('default_brush_size', size);
    } catch (e) {
      print('Failed to save brush size: $e');
    }
  }

  Future<void> _saveBrushColor(Color color) async {
    try {
      final configService = await ConfigService.getInstance();
      await configService.setSetting('default_brush_color', color.value);
    } catch (e) {
      print('Failed to save brush color: $e');
    }
  }



  void _updateCanvasSettings() {
    final canvas = widget.canvasKey.currentState as dynamic;
    if (canvas != null) {
      canvas.setStrokeWidth(_strokeWidth);
      canvas.setPenColor(_penColor);
      canvas.setEraserMode(_isEraserMode);
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
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceVariant,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 4,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 工具栏标题行
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    // 返回按钮（如果提供了回调）
                    if (widget.onBack != null) ...[
                      IconButton(
                        onPressed: widget.onBack,
                        icon: Icon(
                          Icons.arrow_back,
                          size: 20,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        tooltip: '返回',
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          padding: EdgeInsets.zero,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    // 进度显示（如果提供了进度信息）
                    if (widget.progressTitle != null && widget.currentProgress != null && widget.totalProgress != null) ...[
                      Icon(
                        Icons.timeline,
                        size: 20,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${widget.progressTitle}: ${widget.currentProgress}/${widget.totalProgress}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ] else ...[
                      Icon(
                        Icons.build,
                        size: 20,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '工具栏',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    const Spacer(),
                    // 常用操作按钮
                    ..._buildQuickActions(),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showBrushSizePanel() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('画笔大小'),
          content: StatefulBuilder(
            builder: (context, setState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('当前大小: ${_strokeWidth.round()}'),
                  const SizedBox(height: 16),
                  Slider(
                    value: _strokeWidth,
                    min: 1.0,
                    max: 10.0,
                    divisions: 9,
                    onChanged: (value) {
                      setState(() {
                        _strokeWidth = value;
                      });
                      this.setState(() {});
                      _updateCanvasSettings();
                      _saveBrushSize(value);
                    },
                  ),
                ],
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
  }

  void _showColorPanel() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('画笔颜色'),
          content: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Colors.black,
              Colors.red,
              Colors.blue,
              Colors.green,
              Colors.orange,
              Colors.purple,
            ].map((color) => GestureDetector(
              onTap: () {
                setState(() {
                  _penColor = color;
                });
                _updateCanvasSettings();
                // 只在非默写模式下保存颜色设置
                if (!widget.isDictationMode) {
                  _saveBrushColor(color);
                }
                Navigator.of(context).pop();
              },
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _penColor == color 
                        ? Colors.grey.shade800 
                        : Colors.grey.shade300,
                    width: _penColor == color ? 3 : 1,
                  ),
                ),
              ),
            )).toList(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
          ],
        );
      },
    );
  }

  List<Widget> _buildQuickActions() {
    return [
      // 画笔/橡皮切换
      IconButton(
        onPressed: () {
          setState(() {
            _isEraserMode = !_isEraserMode;
          });
          _updateCanvasSettings();
        },
        icon: Icon(
          _isEraserMode ? Icons.auto_fix_normal : Icons.brush,
          size: 20,
        ),
        style: IconButton.styleFrom(
          backgroundColor: _isEraserMode 
              ? Colors.red.withOpacity(0.1) 
              : Colors.blue.withOpacity(0.1),
          foregroundColor: _isEraserMode ? Colors.red : Colors.blue,
        ),
        tooltip: _isEraserMode ? '切换到画笔' : '切换到橡皮',
      ),
      
      // 撤销
      IconButton(
        onPressed: widget.onUndo,
        icon: const Icon(Icons.undo, size: 20),
        tooltip: '撤销',
      ),
      
      // 清空
      IconButton(
        onPressed: widget.onClear,
        icon: const Icon(Icons.clear, size: 20),
        tooltip: '清空画布',
      ),
      
      // 画笔大小设置
      IconButton(
        onPressed: _showBrushSizePanel,
        icon: const Icon(Icons.line_weight, size: 20),
        tooltip: '画笔大小',
      ),
      
      // 画笔颜色设置（仅在非默写模式或非批改状态下显示）
      if (!widget.isDictationMode || !Provider.of<DictationProvider>(context, listen: false).isAnnotationMode)
        IconButton(
          onPressed: _showColorPanel,
          icon: Icon(
            Icons.palette,
            size: 20,
            color: _penColor,
          ),
          tooltip: '画笔颜色',
        ),
    ];
  }




}