import 'package:flutter/material.dart';

class AIGenerateExamplesRequest {
  final String prompt;
  final String answer;
  final String? sourceLanguage;
  final String? targetLanguage;

  AIGenerateExamplesRequest({
    required this.prompt,
    required this.answer,
    this.sourceLanguage,
    this.targetLanguage,
  });
}

/// 统一的「AI生成例句」对话框组件
/// 收集原文、译文与语言选择（常用/自定义），点击「生成」返回请求参数
class AIGenerateExamplesDialog extends StatefulWidget {
  final String initialPrompt;
  final String initialAnswer;

  const AIGenerateExamplesDialog({
    super.key,
    required this.initialPrompt,
    required this.initialAnswer,
  });

  @override
  State<AIGenerateExamplesDialog> createState() => _AIGenerateExamplesDialogState();
}

class _AIGenerateExamplesDialogState extends State<AIGenerateExamplesDialog> {
  late final TextEditingController _promptController;
  late final TextEditingController _answerController;

  String _sourceDropdown = 'auto';
  String _targetDropdown = 'auto';
  final TextEditingController _sourceCustomController = TextEditingController();
  final TextEditingController _targetCustomController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _promptController = TextEditingController(text: widget.initialPrompt);
    _answerController = TextEditingController(text: widget.initialAnswer);
  }

  @override
  void dispose() {
    _promptController.dispose();
    _answerController.dispose();
    _sourceCustomController.dispose();
    _targetCustomController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('AI生成例句'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _promptController,
              decoration: const InputDecoration(
                labelText: '原文',
                hintText: '请输入原文文本',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _answerController,
              decoration: const InputDecoration(
                labelText: '译文（多义用;或；分隔）',
                hintText: '示例：意思1;意思2;意思3',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _sourceDropdown,
                    items: const [
                      DropdownMenuItem(value: 'auto', child: Text('自动识别')),
                      DropdownMenuItem(value: 'ja', child: Text('日语 ja')),
                      DropdownMenuItem(value: 'zh', child: Text('中文 zh')),
                      DropdownMenuItem(value: 'en', child: Text('英语 en')),
                      DropdownMenuItem(value: 'de', child: Text('德语 de')),
                      DropdownMenuItem(value: 'fr', child: Text('法语 fr')),
                      DropdownMenuItem(value: 'ko', child: Text('韩语 ko')),
                      DropdownMenuItem(value: 'custom', child: Text('自定义')),
                    ],
                    onChanged: (v) => setState(() => _sourceDropdown = v ?? 'auto'),
                    decoration: const InputDecoration(
                      labelText: '原文语言（常用）',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _targetDropdown,
                    items: const [
                      DropdownMenuItem(value: 'auto', child: Text('自动识别')),
                      DropdownMenuItem(value: 'zh', child: Text('中文 zh')),
                      DropdownMenuItem(value: 'ja', child: Text('日语 ja')),
                      DropdownMenuItem(value: 'en', child: Text('英语 en')),
                      DropdownMenuItem(value: 'de', child: Text('德语 de')),
                      DropdownMenuItem(value: 'fr', child: Text('法语 fr')),
                      DropdownMenuItem(value: 'ko', child: Text('韩语 ko')),
                      DropdownMenuItem(value: 'custom', child: Text('自定义')),
                    ],
                    onChanged: (v) => setState(() => _targetDropdown = v ?? 'auto'),
                    decoration: const InputDecoration(
                      labelText: '译文语言（常用）',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_sourceDropdown == 'custom')
              TextField(
                controller: _sourceCustomController,
                decoration: const InputDecoration(
                  labelText: '原文语言（自定义代码，可选）',
                  hintText: '如 ja, zh-CN, en-US，留空则自动或常用选择',
                ),
              ),
            if (_targetDropdown == 'custom')
              TextField(
                controller: _targetCustomController,
                decoration: const InputDecoration(
                  labelText: '译文语言（自定义代码，可选）',
                  hintText: '如 zh, en-GB，留空则自动或常用选择',
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final prompt = _promptController.text.trim();
            final answer = _answerController.text.trim();
            if (prompt.isEmpty || answer.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('请填写原文与译文')),
              );
              return;
            }

            final src = _sourceDropdown == 'custom'
                ? _sourceCustomController.text.trim()
                : (_sourceDropdown == 'auto' ? null : _sourceDropdown);
            final tgt = _targetDropdown == 'custom'
                ? _targetCustomController.text.trim()
                : (_targetDropdown == 'auto' ? null : _targetDropdown);

            Navigator.of(context).pop(AIGenerateExamplesRequest(
              prompt: prompt,
              answer: answer,
              sourceLanguage: (src != null && src.isEmpty) ? null : src,
              targetLanguage: (tgt != null && tgt.isEmpty) ? null : tgt,
            ));
          },
          child: const Text('生成'),
        ),
      ],
    );
  }
}