import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../shared/models/dictation_session.dart';
import '../../shared/utils/accuracy_header_utils.dart';

class ShareService {
  static const double _cardWidth = 1200.0;  // 超高分辨率
  static const double _cardHeight = 1800.0; // 超高分辨率
  
  /// 生成分享图片
  static Future<Uint8List> generateShareImage(DictationSession session) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    
    // 获取准确率和颜色
    final accuracy = session.accuracy;
    final headerColor = await AccuracyHeaderUtils.getHeaderColor(accuracy);
    final headerIcon = await AccuracyHeaderUtils.getHeaderIcon(accuracy);
    final headerTitle = await AccuracyHeaderUtils.getHeaderTitle(accuracy);
    final headerSubtitle = await AccuracyHeaderUtils.getHeaderSubtitle(accuracy);
    
    // 绘制背景
    final backgroundPaint = Paint()..color = headerColor;
    canvas.drawRect(Rect.fromLTWH(0, 0, _cardWidth, _cardHeight), backgroundPaint);
    
    // 绘制头部背景
    final headerPaint = Paint()..color = headerColor;
    const headerHeight = 600.0; // 增加头部高度以容纳所有内容
    final headerRect = RRect.fromRectAndCorners(
      Rect.fromLTWH(0, 0, _cardWidth, headerHeight),
      bottomLeft: const Radius.circular(20),
      bottomRight: const Radius.circular(20),
    );
    canvas.drawRRect(headerRect, headerPaint);
    
    // 绘制图标（调整大小适应超高分辨率）
    await _drawIcon(canvas, headerIcon, 120.0, _cardWidth / 2, 120.0, Colors.white);
    
    // 绘制标题
    await _drawText(
      canvas,
      headerTitle,
      _cardWidth / 2,
      280.0,
      64.0,
      Colors.white,
      FontWeight.bold,
      TextAlign.center,
    );
    
    // 绘制文件名（如果有）
    if (session.wordFileName != null) {
      await _drawFileNameBadge(canvas, session.wordFileName!, _cardWidth / 2, 380.0);
    }
    
    // 绘制副标题
    await _drawText(
      canvas,
      headerSubtitle,
      _cardWidth / 2,
      session.wordFileName != null ? 480.0 : 380.0,
      42.0,
      Colors.white70,
      FontWeight.normal,
      TextAlign.center,
    );
    
    // 绘制统计卡片
    await _drawStatCards(canvas, session, headerColor);
    
    // 绘制时间信息
    await _drawTimeCards(canvas, session, headerColor);
    
    // 绘制准确率
    await _drawAccuracySection(canvas, accuracy, headerColor);
    
    // 绘制底部水印
    await _drawWatermark(canvas);
    
    final picture = recorder.endRecording();
    final img = await picture.toImage(_cardWidth.toInt(), _cardHeight.toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    
    return byteData!.buffer.asUint8List();
  }
  
  /// 分享到其他应用
  static Future<void> shareToApps(DictationSession session) async {
    try {
      final imageBytes = await generateShareImage(session);
      final tempDir = await getTemporaryDirectory();
      final fileName = 'dictation_result_${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(imageBytes);
      
      // 确保文件存在且有内容
      if (!await file.exists() || await file.length() == 0) {
        throw Exception('生成的图片文件无效');
      }
      
      await Share.shareXFiles(
        [XFile(file.path, name: fileName, mimeType: 'image/png')],
        text: '我的默写成绩：准确率${session.accuracy.toInt()}%，正确${session.correctCount}题，错误${session.incorrectCount}题',
        subject: '单词默写成绩分享',
      );
    } catch (e) {
      throw Exception('分享失败: $e');
    }
  }
  
  /// 保存图片到本地（支持选择路径和自定义文件名）
  static Future<String?> saveToLocal(DictationSession session, {String? customPath, String? customFileName}) async {
    try {
      // 如果没有提供自定义路径，则用户取消了选择，直接返回null
      if (customPath == null) {
        return null;
      }
      
      final imageBytes = await generateShareImage(session);
      
      // 使用自定义文件名或默认文件名
      final fileName = customFileName ?? 'dictation_result_${DateTime.now().millisecondsSinceEpoch}.png';
      
      // 确保文件名以.png结尾
      final finalFileName = fileName.endsWith('.png') ? fileName : '$fileName.png';
      
      final filePath = '$customPath/$finalFileName';
      final file = File(filePath);
      await file.writeAsBytes(imageBytes);
      
      return file.path;
    } catch (e) {
      throw Exception('保存失败: $e');
    }
  }
  
  /// 复制图片数据到剪贴板
  static Future<void> copyToClipboard(DictationSession session) async {
    try {
      final imageBytes = await generateShareImage(session);
      
      // 在Windows平台上，我们需要将图片保存为临时文件并复制路径
      // 因为Flutter的Clipboard API在Windows上不直接支持图片数据
      if (Platform.isWindows) {
        final tempDir = await getTemporaryDirectory();
        final fileName = 'dictation_result_${DateTime.now().millisecondsSinceEpoch}.png';
        final file = File('${tempDir.path}/$fileName');
        await file.writeAsBytes(imageBytes);
        
        // 使用Windows特定的方法复制图片到剪贴板
        await _copyImageToClipboardWindows(file.path);
      } else {
        // 对于其他平台，尝试直接复制图片数据
        // 注意：这在某些平台上可能不被支持
        throw UnsupportedError('图片复制功能暂不支持当前平台');
      }
    } catch (e) {
      throw Exception('复制失败: $e');
    }
  }
  
  /// Windows平台特定的图片复制方法
  static Future<void> _copyImageToClipboardWindows(String imagePath) async {
    try {
      // 使用PowerShell命令将图片复制到剪贴板
      final result = await Process.run('powershell', [
        '-Command',
        'Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.Clipboard]::SetImage([System.Drawing.Image]::FromFile("$imagePath"))'
      ]);
      
      if (result.exitCode != 0) {
        throw Exception('PowerShell命令执行失败: ${result.stderr}');
      }
    } catch (e) {
      throw Exception('Windows图片复制失败: $e');
    }
  }
  
  // 私有辅助方法
  static Future<void> _drawIcon(Canvas canvas, IconData iconData, double size, double x, double y, Color color) async {
    final textPainter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(iconData.codePoint),
        style: TextStyle(
          fontFamily: 'MaterialIcons',
          fontSize: size,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(x - textPainter.width / 2, y));
  }
  
  static Future<void> _drawText(
    Canvas canvas,
    String text,
    double x,
    double y,
    double fontSize,
    Color color,
    FontWeight fontWeight,
    TextAlign textAlign,
  ) async {
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          color: color,
          fontWeight: fontWeight,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: textAlign,
    );
    textPainter.layout(maxWidth: _cardWidth - 40);
    
    double offsetX = x;
    if (textAlign == TextAlign.center) {
      offsetX = x - textPainter.width / 2;
    }
    
    textPainter.paint(canvas, Offset(offsetX, y));
  }
  
  static Future<void> _drawFileNameBadge(Canvas canvas, String fileName, double x, double y) async {
    const badgeHeight = 72.0;
    const badgePadding = 36.0;
    
    // 计算文本宽度
    final textPainter = TextPainter(
      text: TextSpan(
        text: fileName,
        style: const TextStyle(
          fontSize: 36,
          color: Colors.white70,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    
    final badgeWidth = textPainter.width + badgePadding * 2 + 20; // 20 for icon
    
    // 绘制背景
    final badgePaint = Paint()..color = Colors.white.withOpacity(0.2);
    final badgeRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(x, y + badgeHeight / 2),
        width: badgeWidth,
        height: badgeHeight,
      ),
      const Radius.circular(12),
    );
    canvas.drawRRect(badgeRect, badgePaint);
    
    // 绘制图标
    await _drawIcon(canvas, Icons.description, 48.0, x - textPainter.width / 2 - 18, y + 12, Colors.white70);
    
    // 绘制文本
    textPainter.paint(canvas, Offset(x - textPainter.width / 2 + 30, y + 15));
  }
  
  static Future<void> _drawStatCards(Canvas canvas, DictationSession session, Color headerColor) async {
    const cardY = 720.0;
    const cardWidth = 240.0;
    const cardHeight = 180.0;
    const spacing = 40.0;
    
    // 重新计算X坐标，确保4个卡片能在1200像素宽度内正确显示
    final totalWidth = cardWidth * 4 + spacing * 3;
    final startX = (_cardWidth - totalWidth) / 2;
    
    final totalX = startX;
    final timeX = totalX + cardWidth + spacing;
    final correctX = timeX + cardWidth + spacing;
    final incorrectX = correctX + cardWidth + spacing;
    
    // 总题数
    await _drawStatCard(canvas, totalX, cardY, cardWidth, cardHeight, Icons.quiz, '总题数', session.totalWords.toString(), headerColor);
    
    // 用时
    final duration = session.duration;
    final durationText = duration != null
        ? '${duration.inMinutes}分${duration.inSeconds % 60}秒'
        : '未知';
    await _drawStatCard(canvas, timeX, cardY, cardWidth, cardHeight, Icons.timer, '用时', durationText, headerColor);
    
    // 正确
    await _drawStatCard(canvas, correctX, cardY, cardWidth, cardHeight, Icons.check_circle, '正确', session.correctCount.toString(), headerColor);
    
    // 错误
    await _drawStatCard(canvas, incorrectX, cardY, cardWidth, cardHeight, Icons.cancel, '错误', session.incorrectCount.toString(), headerColor);
  }
  
  static Future<void> _drawStatCard(
    Canvas canvas,
    double x,
    double y,
    double width,
    double height,
    IconData icon,
    String label,
    String value,
    Color headerColor,
  ) async {
    // 绘制卡片背景（白色透明）
    final cardPaint = Paint()..color = Colors.white.withOpacity(0.2);
    final cardRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(x, y, width, height),
      const Radius.circular(8),
    );
    canvas.drawRRect(cardRect, cardPaint);
    
    // 绘制图标
    await _drawIcon(canvas, icon, 48.0, x + width / 2, y + 32, Colors.white);
    
    // 绘制数值
    await _drawText(canvas, value, x + width / 2, y + 90, 36.0, Colors.white, FontWeight.bold, TextAlign.center);
    
    // 绘制标签
    await _drawText(canvas, label, x + width / 2, y + 140, 28.0, Colors.white70, FontWeight.normal, TextAlign.center);
  }
  
  static Future<void> _drawTimeCards(Canvas canvas, DictationSession session, Color headerColor) async {
    const cardY = 960.0;
    const cardWidth = 360.0;
    const cardHeight = 180.0;
    const spacing = 60.0;
    
    // 重新计算X坐标，确保2个卡片能在1200像素宽度内正确显示
    final totalWidth = cardWidth * 2 + spacing;
    final startX = (_cardWidth - totalWidth) / 2;
    final endX = startX + cardWidth + spacing;
    
    // 开始时间
    final startTime = _formatTime(session.startTime);
    await _drawStatCard(canvas, startX, cardY, cardWidth, cardHeight, Icons.play_arrow, '开始时间', startTime, headerColor);
    
    // 结束时间
    final endTime = session.endTime != null ? _formatTime(session.endTime!) : '未完成';
    await _drawStatCard(canvas, endX, cardY, cardWidth, cardHeight, Icons.stop, '结束时间', endTime, headerColor);
  }
  
  static Future<void> _drawAccuracySection(Canvas canvas, double accuracy, Color headerColor) async {
    const sectionY = 1200.0;
    const sectionWidth = 960.0;
    const sectionHeight = 240.0;
    
    final sectionX = (_cardWidth - sectionWidth) / 2;
    
    // 绘制背景（白色透明）
    final sectionPaint = Paint()..color = Colors.white.withOpacity(0.2);
    final sectionRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(sectionX, sectionY, sectionWidth, sectionHeight),
      const Radius.circular(12),
    );
    canvas.drawRRect(sectionRect, sectionPaint);
    
    // 绘制准确率图标和标题
    await _drawIcon(canvas, Icons.percent, 36.0, _cardWidth / 2 - 70, sectionY + 50, Colors.white);
    await _drawText(canvas, '准确率', _cardWidth / 2 + 20, sectionY + 50, 36.0, Colors.white, FontWeight.bold, TextAlign.left);
    
    // 绘制准确率数值
    await _drawText(canvas, '${accuracy.toInt()}%', _cardWidth / 2, sectionY + 110, 56.0, Colors.white, FontWeight.bold, TextAlign.center);
    
    // 绘制进度条
    const progressY = sectionY + 195;
    const progressWidth = 840.0;
    const progressHeight = 18.0;
    final progressX = (_cardWidth - progressWidth) / 2;
    
    // 进度条背景
    final progressBgPaint = Paint()..color = Colors.white.withOpacity(0.3);
    final progressBgRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(progressX, progressY, progressWidth, progressHeight),
      const Radius.circular(3),
    );
    canvas.drawRRect(progressBgRect, progressBgPaint);
    
    // 进度条前景
    final progressPaint = Paint()..color = Colors.white;
    final progressRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(progressX, progressY, progressWidth * (accuracy / 100), progressHeight),
      const Radius.circular(3),
    );
    canvas.drawRRect(progressRect, progressPaint);
  }
  
  static Future<void> _drawWatermark(Canvas canvas) async {
    final sectionPaint = Paint()..color = Colors.white.withOpacity(0.2);
    final sectionRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0.0, _cardHeight - 90, _cardWidth, 90.0),
      const Radius.circular(0),
    );
    canvas.drawRRect(sectionRect, sectionPaint);

    await _drawText(
      canvas,
      '单词默写助手',
      _cardWidth / 2,
      _cardHeight - 80,
      36.0,
      Colors.white70,
      FontWeight.normal,
      TextAlign.center,
    );
  }
  
  static String _formatTime(DateTime dateTime) {
    return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
}