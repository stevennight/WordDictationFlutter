import 'package:flutter/material.dart';

/// AI 生成词解的策略选择对话框
/// 返回：'overwrite' | 'skip'
class AIGenerateExplanationsStrategyDialog extends StatelessWidget {
  final String title;
  final String description;

  const AIGenerateExplanationsStrategyDialog({
    super.key,
    this.title = 'AI生成词解策略',
    this.description = '选择策略：覆盖或在已存在词解时跳过。',
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title),
      content: Text(description),
      actions: [
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

/// 便捷方法：弹出 AI 生成词解策略选择对话框
Future<String> pickAIGenerateExplanationsStrategy(BuildContext context, {String defaultValue = 'skip'}) async {
  final res = await showDialog<String>(
    context: context,
    builder: (context) => const AIGenerateExplanationsStrategyDialog(),
  );
  return res ?? defaultValue;
}