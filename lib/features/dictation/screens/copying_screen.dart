import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../shared/providers/dictation_provider.dart';
import '../../../shared/widgets/handwriting_canvas.dart';
import '../../../shared/widgets/unified_canvas_toolbar.dart';
import '../widgets/dictation_progress.dart';

class CopyingScreen extends StatefulWidget {
  const CopyingScreen({super.key});

  @override
  State<CopyingScreen> createState() => _CopyingScreenState();
}

class _CopyingScreenState extends State<CopyingScreen> {
  late DictationProvider _provider;
  final GlobalKey<State<HandwritingCanvas>> _canvasKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _provider = context.read<DictationProvider>();
      if (_provider.hasWords) {
        _provider.initializeCopying(_provider.words, 0);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('抄写练习'),
      ),
      body: Consumer<DictationProvider>(
        builder: (context, provider, child) {
          if (provider.currentWord == null) {
            return const Center(
              child: CircularProgressIndicator(),
            );
  }

          return Column(
            children: [
              // Progress bar
              DictationProgress(
                current: provider.currentIndex,
                total: provider.totalWords,
                correct: 0, // 抄写模式不显示正确数
                incorrect: 0, // 抄写模式不显示错误数
                showStats: false, // 隐藏统计信息
              ),
              
              // Main content
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      // Word display section
                      _buildWordSection(provider),
                      
                      const SizedBox(height: 16),
                      
                      // Canvas section
                      Expanded(
                        child: _buildCanvasSection(provider),
                      ),
                      
                      const SizedBox(height: 16),
                      
                      // Action buttons
                      _buildActionButtons(provider),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildWordSection(DictationProvider provider) {
    final word = provider.currentWord!;
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 词性和等级信息行
            Row(
              children: [
                Icon(
                  Icons.quiz,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                
                // 词性
                if (word.partOfSpeech != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      word.partOfSpeech!,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSecondaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                
                if (word.partOfSpeech != null && word.level != null)
                  const SizedBox(width: 8),
                  
                // 等级
                if (word.level != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.tertiaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      word.level!,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onTertiaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
            
            const SizedBox(height: 12),
            
            // 译文和原文行
            Row(
              children: [
                 // 译文
                Expanded(
                  flex: 2,
                  child: Text(
                    word.answer,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                
                const SizedBox(width: 12),
                
                // 原文（可点击全屏查看）
                Expanded(
                  flex: 3,
                  child: GestureDetector(
                    onTap: () => _showFullScreenText(word.prompt),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                        ),
                      ),
                      child: Text(
                        word.prompt,
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCanvasSection(DictationProvider provider) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // 统一工具栏
            UnifiedCanvasToolbar(
              canvasKey: _canvasKey,
              isDictationMode: false,
              showDictationControls: false,
            ),
            
            const SizedBox(height: 16),
            
            // Canvas
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: HandwritingCanvas(
                    key: _canvasKey,
                    width: double.infinity,
                    height: 300,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(DictationProvider provider) {
    final isLastWord = provider.currentIndex >= provider.totalWords - 1;
    
    return Row(
      children: [
        // Previous button
        if (provider.currentIndex > 0)
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () {
                (_canvasKey.currentState as dynamic)?.clearCanvas();
                provider.goToPreviousWord();
              },
              icon: const Icon(Icons.arrow_back),
              label: const Text('上一个'),
            ),
          ),
        
        if (provider.currentIndex > 0) const SizedBox(width: 12),
        
        // Next/Finish button
        Expanded(
          flex: 2,
          child: ElevatedButton.icon(
            onPressed: () {
              if (isLastWord) {
                _finishCopying();
              } else {
                (_canvasKey.currentState as dynamic)?.clearCanvas();
                provider.goToNextWord();
              }
            },
            icon: Icon(isLastWord ? Icons.check : Icons.arrow_forward),
            label: Text(isLastWord ? '完成抄写' : '下一个'),
          ),
        ),
      ],
    );
  }

  void _showFullScreenText(String text) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Container(
            width: double.infinity,
            height: double.infinity,
            color: Colors.black54,
            child: Center(
              child: Container(
                margin: const EdgeInsets.all(32),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '原文内容',
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            color: Colors.blue.shade700,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close),
                          color: Colors.grey.shade600,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.blue.withOpacity(0.3),
                          width: 2,
                        ),
                      ),
                      child: Text(
                        text,
                        style: Theme.of(context).textTheme.displaySmall?.copyWith(
                          color: Colors.blue.shade700,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '点击任意位置关闭',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade600,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _finishCopying() {
    // 抄写模式不记录到历史记录中，直接显示完成对话框
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('抄写完成'),
        content: const Text('恭喜你完成了所有单词的抄写！'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(); // Close dialog
              Navigator.of(context).pop(); // Return to previous screen
            },
            child: const Text('返回'),
          ),
        ],
      ),
    );
  }
}