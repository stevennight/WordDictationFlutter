import 'package:flutter/material.dart';

import '../../core/services/word_service.dart';
import '../../shared/models/word.dart';
import '../../features/word/word_detail_screen.dart';

/// 统一的“按原文查找并打开单词详情”工具
class WordNavigationUtils {
  /// 通过单词原文（prompt）查找并打开详情页面
  /// - 优先精确匹配（忽略大小写）
  /// - 若存在多条，取第一条
  /// - 若找不到则提示
  static Future<void> openWordDetailByText(
    BuildContext context,
    String text,
  ) async {
    final query = text.trim();
    if (query.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未找到该单词：原文为空')),
      );
      return;
    }

    try {
      final service = WordService();
      final candidates = await service.searchWords(query);

      if (candidates.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('未找到该单词：$query')),
        );
        return;
      }

      // 优先选择原文精确匹配（忽略大小写），否则取第一条
      final lower = query.toLowerCase();
      final Word chosen = candidates.firstWhere(
        (w) => w.prompt.toLowerCase() == lower,
        orElse: () => candidates.first,
      );

      // 进入详情
      // ignore: use_build_context_synchronously
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => WordDetailScreen(word: chosen),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('打开详情失败：$e')),
      );
    }
  }
}