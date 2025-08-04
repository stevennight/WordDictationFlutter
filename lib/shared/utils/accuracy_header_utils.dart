import 'package:flutter/material.dart';
import '../../core/services/local_config_service.dart';

class AccuracyHeaderUtils {
  static Future<Color> getHeaderColor(double accuracy) async {
    final configService = await LocalConfigService.getInstance();
    final ranges = await configService.getAccuracyColorRanges();
    // accuracy已经是百分比值(0-100)，不需要再乘以100
    
    // 使用严格的区间判断，避免边界值重叠
    if (accuracy >= ranges['green']!['min']!) {
      return Colors.green;
    } else if (accuracy >= ranges['blue']!['min']!) {
      return Colors.blue;
    } else if (accuracy >= ranges['yellow']!['min']!) {
      return Colors.yellow[700]!;
    } else {
      return Colors.red;
    }
  }

  static Future<IconData> getHeaderIcon(double accuracy) async {
    final configService = await LocalConfigService.getInstance();
    final ranges = await configService.getAccuracyColorRanges();
    // accuracy已经是百分比值(0-100)，不需要再乘以100
    
    // 使用严格的区间判断，避免边界值重叠
    if (accuracy >= ranges['green']!['min']!) {
      return Icons.emoji_events;
    } else if (accuracy >= ranges['blue']!['min']!) {
      return Icons.thumb_up;
    } else if (accuracy >= ranges['yellow']!['min']!) {
      return Icons.sentiment_neutral;
    } else {
      return Icons.sentiment_dissatisfied;
    }
  }

  static Future<String> getHeaderTitle(double accuracy, {bool isCompletion = false}) async {
    final configService = await LocalConfigService.getInstance();
    final ranges = await configService.getAccuracyColorRanges();
    // accuracy已经是百分比值(0-100)，不需要再乘以100
    
    // 使用严格的区间判断，避免边界值重叠
    if (accuracy >= ranges['green']!['min']!) {
      return isCompletion ? '太棒了！' : '优秀！';
    } else if (accuracy >= ranges['blue']!['min']!) {
      return isCompletion ? '不错！' : '良好！';
    } else if (accuracy >= ranges['yellow']!['min']!) {
      return '还可以';
    } else {
      return '继续努力！';
    }
  }

  static Future<String> getHeaderSubtitle(double accuracy) async {
    final configService = await LocalConfigService.getInstance();
    final ranges = await configService.getAccuracyColorRanges();
    // accuracy已经是百分比值(0-100)，不需要再乘以100
    
    // 使用严格的区间判断，避免边界值重叠
    if (accuracy >= ranges['green']!['min']!) {
      return '你的表现非常出色';
    } else if (accuracy >= ranges['blue']!['min']!) {
      return '你的表现还不错';
    } else if (accuracy >= ranges['yellow']!['min']!) {
      return '还有提升空间';
    } else {
      return '多练习会更好';
    }
  }
}