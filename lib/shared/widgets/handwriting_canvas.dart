import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

  DrawingPoint({
    required this.offset,
    required this.paint,
    this.isEraser = false,
  });
}

class HandwritingCanvas extends StatefulWidget {
  final double? width;
  final double? height;
  final Color backgroundColor;
  final Function(String?)? onImageSaved;
  final bool isAnnotationMode;

  const HandwritingCanvas({
    super.key,
    this.width,
    this.height,
    this.backgroundColor = Colors.white,
    this.onImageSaved,
    this.isAnnotationMode = false,
  });

  @override
  State<HandwritingCanvas> createState() => _HandwritingCanvasState();
}

class _HandwritingCanvasState extends State<HandwritingCanvas> {
  final GlobalKey _canvasKey = GlobalKey();
  List<List<DrawingPoint>> _strokes = [];
  List<DrawingPoint> _currentStroke = [];
  
  DrawingMode _drawingMode = DrawingMode.pen;
  double _strokeWidth = 3.0;
  Color _strokeColor = Colors.black;
  Color _annotationColor = Colors.red;
  
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
    
    _currentStroke = [];
    _addPoint(localPosition);
  }

  void _onPanUpdate(DragUpdateDetails details) {
    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final localPosition = renderBox.globalToLocal(details.globalPosition);
    
    _addPoint(localPosition);
  }

  void _onPanEnd(DragEndDetails details) {
    if (_currentStroke.isNotEmpty) {
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

    if (_drawingMode == DrawingMode.eraser) {
      paint.blendMode = BlendMode.clear;
    }

    final point = DrawingPoint(
      offset: offset,
      paint: paint,
      isEraser: _drawingMode == DrawingMode.eraser,
    );

    setState(() {
      _currentStroke.add(point);
    });
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
      _strokes.clear();
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
        _strokes.removeLast();
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
      
      // Get the app's documents directory
      final Directory appDocDir = await getApplicationDocumentsDirectory();
      final Directory imageDir = Directory(path.join(appDocDir.path, 'handwriting_cache'));
      
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

  HandwritingPainter({
    required this.strokes,
    required this.currentStroke,
    required this.backgroundColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Fill background
    final backgroundPaint = Paint()..color = backgroundColor;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), backgroundPaint);

    // Draw completed strokes
    for (final stroke in strokes) {
      _drawStroke(canvas, stroke);
    }

    // Draw current stroke
    if (currentStroke.isNotEmpty) {
      _drawStroke(canvas, currentStroke);
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