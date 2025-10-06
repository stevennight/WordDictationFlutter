import 'package:flutter/material.dart';

/// AI 生成例句的策略选择对话框
/// 返回：'append' | 'overwrite' | 'skip'
class AIGenerateExamplesStrategyDialog extends StatelessWidget {
  final String title;
  final String description;

  const AIGenerateExamplesStrategyDialog({
    super.key,
    this.title = 'AI生成例句策略',
    this.description = '选择策略：追加、覆盖或在已存在例句时跳过。',
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title),
      content: Text(description),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop('append'),
          child: const Text('追加'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop('overwrite'),
          child: const Text('覆盖'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop('skip'),
          child: const Text('跳过'),
        ),
      ],
    );
  }
}

/// 便捷方法：弹出 AI 生成例句策略选择对话框
Future<String> pickAIGenerateExamplesStrategy(BuildContext context, {String defaultValue = 'append'}) async {
  final res = await showDialog<String>(
    context: context,
    builder: (context) => const AIGenerateExamplesStrategyDialog(),
  );
  return res ?? defaultValue;
}