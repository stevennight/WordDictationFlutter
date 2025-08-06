import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../enums/pen_mode.dart';

enum DrawingMode {
  pen,
  eraser,
}

class DrawingPoint {
  final Offset offset;
  final Paint paint;
  final bool isEraser;
  final bool isAnnotation; // 标识是否为批改笔迹

  DrawingPoint({
    required this.offset,
    required this.paint,
    this.isEraser = false,
    this.isAnnotation = false,
  });
}

class HandwritingCanvas extends StatefulWidget {
  final double? width;
  final double? height;
  final Color backgroundColor;
  final Function(String?)? onImageSaved;
  final bool isAnnotationMode;
  final String? backgroundImagePath;

  const HandwritingCanvas({
    super.key,
    this.width,
    this.height,
    this.backgroundColor = Colors.white,
    this.onImageSaved,
    this.isAnnotationMode = false,
    this.backgroundImagePath,
  });

  @override
  State<HandwritingCanvas> createState() => _HandwritingCanvasState();
}

class _HandwritingCanvasState extends State<HandwritingCanvas> {
  final GlobalKey _canvasKey = GlobalKey();
  List<List<DrawingPoint>> _strokes = [];
  List<DrawingPoint> _currentStroke = [];
  DrawingMode _drawingMode = DrawingMode.pen;
  double _strokeWidth = 2.0;
  Color _strokeColor = Colors.black;
  Color _annotationColor = Colors.red;
  bool _isErasing = false;
  ui.Image? _backgroundImage;
  
  @override
  void initState() {
    super.initState();
    if (widget.backgroundImagePath != null) {
      _loadBackgroundImage();
    }
  }
  
  @override
  void didUpdateWidget(HandwritingCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.backgroundImagePath != oldWidget.backgroundImagePath) {
      if (widget.backgroundImagePath != null) {
        _loadBackgroundImage();
      } else {
        setState(() {
          _backgroundImage = null;
        });
      }
    }
  }
  
  void _loadBackgroundImage() async {
    if (widget.backgroundImagePath == null) return;
    
    try {
      final File imageFile = File(widget.backgroundImagePath!);
      if (await imageFile.exists()) {
        final Uint8List bytes = await imageFile.readAsBytes();
        final ui.Codec codec = await ui.instantiateImageCodec(bytes);
        final ui.FrameInfo frameInfo = await codec.getNextFrame();
        setState(() {
          _backgroundImage = frameInfo.image;
        });
      }
    } catch (e) {
      debugPrint('Error loading background image: $e');
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: widget.backgroundColor,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: GestureDetector(
          onPanStart: _onPanStart,
          onPanUpdate: _onPanUpdate,
          onPanEnd: _onPanEnd,
          child: RepaintBoundary(
            key: _canvasKey,
            child: CustomPaint(
              painter: HandwritingPainter(
                strokes: _strokes,
                currentStroke: _currentStroke,
                backgroundColor: widget.backgroundColor,
                backgroundImage: _backgroundImage,
              ),
              size: Size.infinite,
            ),
          ),
        ),
      ),
    );
  }

  void _onPanStart(DragStartDetails details) {
    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final localPosition = renderBox.globalToLocal(details.globalPosition);
    
    if (_drawingMode == DrawingMode.eraser) {
      _eraseAtPoint(localPosition);
    } else {
      _currentStroke = [];
      _addPoint(localPosition);
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final localPosition = renderBox.globalToLocal(details.globalPosition);
    
    if (_drawingMode == DrawingMode.eraser) {
      _eraseAtPoint(localPosition);
    } else {
      _addPoint(localPosition);
    }
  }

  void _onPanEnd(DragEndDetails details) {
    if (_drawingMode != DrawingMode.eraser && _currentStroke.isNotEmpty) {
      setState(() {
        _strokes.add(List.from(_currentStroke));
        _currentStroke = [];
      });
    }
  }

  void _addPoint(Offset offset) {
    final paint = Paint()
      ..color = widget.isAnnotationMode ? _annotationColor : _strokeColor
      ..strokeWidth = _strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final point = DrawingPoint(
      offset: offset,
      paint: paint,
      isEraser: false,
      isAnnotation: widget.isAnnotationMode, // 标记是否为批改笔迹
    );

    setState(() {
      _currentStroke.add(point);
    });
  }

  void _eraseAtPoint(Offset point) {
    final eraserRadius = _strokeWidth;
    final List<int> strokesToRemove = [];
    
    for (int i = 0; i < _strokes.length; i++) {
      final stroke = _strokes[i];
      if (stroke.isEmpty) continue;
      
      // 在批改模式下，只能擦除批改笔迹
      if (widget.isAnnotationMode && !stroke.first.isAnnotation) {
        continue;
      }
      
      // 检查笔迹是否与橡皮擦区域相交
      bool shouldErase = false;
      for (final strokePoint in stroke) {
        final distance = (strokePoint.offset - point).distance;
        if (distance <= eraserRadius) {
          shouldErase = true;
          break;
        }
      }
      
      if (shouldErase) {
        strokesToRemove.add(i);
      }
    }
    
    if (strokesToRemove.isNotEmpty) {
      setState(() {
        // 从后往前删除，避免索引问题
        for (int i = strokesToRemove.length - 1; i >= 0; i--) {
          _strokes.removeAt(strokesToRemove[i]);
        }
      });
    }
  }

  // Public methods for controlling the canvas
  void setDrawingMode(DrawingMode mode) {
    setState(() {
      _drawingMode = mode;
    });
  }

  void setStrokeWidth(double width) {
    setState(() {
      _strokeWidth = width;
    });
  }

  void setStrokeColor(Color color) {
    setState(() {
      _strokeColor = color;
    });
  }

  void setAnnotationColor(Color color) {
    setState(() {
      _annotationColor = color;
    });
  }

  void setPenMode(PenMode mode) {
    setState(() {
      _drawingMode = mode == PenMode.pen ? DrawingMode.pen : DrawingMode.eraser;
    });
  }

  void setPenSize(double size) {
    setStrokeWidth(size);
  }

  void setPenColor(Color color) {
    setStrokeColor(color);
  }

  void setEraserSize(double size) {
    setState(() {
      _strokeWidth = size;
    });
  }

  void clear() {
    clearCanvas();
  }

  void clearCanvas() {
    setState(() {
      if (widget.isAnnotationMode) {
        // 批改模式下只清空批改笔迹
        _strokes.removeWhere((stroke) => 
          stroke.isNotEmpty && stroke.first.isAnnotation);
      } else {
        // 默写模式下清空所有笔迹
        _strokes.clear();
      }
      _currentStroke.clear();
    });
  }

  void clearAnnotations() {
    if (widget.isAnnotationMode) {
      setState(() {
        _strokes.removeWhere((stroke) => 
          stroke.isNotEmpty && stroke.first.paint.color == _annotationColor);
      });
    }
  }

  void undo() {
    if (_strokes.isNotEmpty) {
      setState(() {
        if (widget.isAnnotationMode) {
          // 批改模式下只能撤销批改笔迹
          for (int i = _strokes.length - 1; i >= 0; i--) {
            if (_strokes[i].isNotEmpty && _strokes[i].first.isAnnotation) {
              _strokes.removeAt(i);
              break;
            }
          }
        } else {
          // 默写模式下可以撤销所有笔迹
          _strokes.removeLast();
        }
      });
    }
  }

  bool get isEmpty => _strokes.isEmpty && _currentStroke.isEmpty;
  bool get isNotEmpty => !isEmpty;

  Future<String?> saveAsImage(String fileName) async {
    try {
      final RenderRepaintBoundary boundary = _canvasKey.currentContext
          ?.findRenderObject() as RenderRepaintBoundary;
      
      final ui.Image image = await boundary.toImage(pixelRatio: 2.0);
      final ByteData? byteData = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      
      if (byteData == null) return null;
      
      final Uint8List pngBytes = byteData.buffer.asUint8List();
      
      // Get the app directory (same logic as database and config)
      String appDir;
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        // Get executable directory for desktop platforms
        final executablePath = Platform.resolvedExecutable;
        appDir = path.dirname(executablePath);
      } else {
        // Fallback to documents directory for mobile platforms
        final documentsDirectory = await getApplicationDocumentsDirectory();
        appDir = documentsDirectory.path;
      }
      final Directory imageDir = Directory(path.join(appDir, 'handwriting_cache'));
      
      // Create directory if it doesn't exist
      if (!await imageDir.exists()) {
        await imageDir.create(recursive: true);
      }
      
      // Save the image
      final String filePath = path.join(imageDir.path, fileName);
      final File file = File(filePath);
      await file.writeAsBytes(pngBytes);
      
      widget.onImageSaved?.call(filePath);
      return filePath;
    } catch (e) {
      debugPrint('Error saving canvas image: $e');
      widget.onImageSaved?.call(null);
      return null;
    }
  }
}

class HandwritingPainter extends CustomPainter {
  final List<List<DrawingPoint>> strokes;
  final List<DrawingPoint> currentStroke;
  final Color backgroundColor;
  final ui.Image? backgroundImage;

  HandwritingPainter({
    required this.strokes,
    required this.currentStroke,
    required this.backgroundColor,
    this.backgroundImage,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Fill background
    final backgroundPaint = Paint()..color = backgroundColor;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), backgroundPaint);

    // Draw background image if provided
    if (backgroundImage != null) {
      _drawBackgroundImage(canvas, size);
    }

    // Draw completed strokes
    for (final stroke in strokes) {
      _drawStroke(canvas, stroke);
    }

    // Draw current stroke
    if (currentStroke.isNotEmpty) {
      _drawStroke(canvas, currentStroke);
    }
  }

  void _drawBackgroundImage(Canvas canvas, Size size) {
    if (backgroundImage != null) {
      final double imageWidth = backgroundImage!.width.toDouble();
      final double imageHeight = backgroundImage!.height.toDouble();
      
      // Calculate scale to fit the image within the canvas while maintaining aspect ratio
      final double scaleX = size.width / imageWidth;
      final double scaleY = size.height / imageHeight;
      final double scale = scaleX < scaleY ? scaleX : scaleY;
      
      final double scaledWidth = imageWidth * scale;
      final double scaledHeight = imageHeight * scale;
      
      // Center the image
      final double offsetX = (size.width - scaledWidth) / 2;
      final double offsetY = (size.height - scaledHeight) / 2;
      
      final Rect srcRect = Rect.fromLTWH(0, 0, imageWidth, imageHeight);
      final Rect dstRect = Rect.fromLTWH(offsetX, offsetY, scaledWidth, scaledHeight);
      
      canvas.drawImageRect(backgroundImage!, srcRect, dstRect, Paint());
    }
  }

  void _drawStroke(Canvas canvas, List<DrawingPoint> stroke) {
    if (stroke.isEmpty) return;

    if (stroke.length == 1) {
      // Draw a single point
      final point = stroke.first;
      canvas.drawCircle(
        point.offset,
        point.paint.strokeWidth / 2,
        point.paint,
      );
    } else {
      // Draw connected lines
      final path = Path();
      path.moveTo(stroke.first.offset.dx, stroke.first.offset.dy);
      
      for (int i = 1; i < stroke.length; i++) {
        final current = stroke[i];
        final previous = stroke[i - 1];
        
        // Use quadratic bezier curves for smoother lines
        final controlPoint = Offset(
          (previous.offset.dx + current.offset.dx) / 2,
          (previous.offset.dy + current.offset.dy) / 2,
        );
        
        if (i == 1) {
          path.lineTo(controlPoint.dx, controlPoint.dy);
        } else {
          path.quadraticBezierTo(
            previous.offset.dx,
            previous.offset.dy,
            controlPoint.dx,
            controlPoint.dy,
          );
        }
      }
      
      // Draw the final segment
      final lastPoint = stroke.last;
      path.lineTo(lastPoint.offset.dx, lastPoint.offset.dy);
      
      canvas.drawPath(path, stroke.first.paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}