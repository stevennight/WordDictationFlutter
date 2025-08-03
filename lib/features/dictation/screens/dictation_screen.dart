import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../shared/models/dictation_session.dart';
import '../../../shared/models/word.dart';
import '../../../shared/providers/dictation_provider.dart';
import '../../../shared/providers/app_state_provider.dart';
import '../../../shared/widgets/handwriting_canvas.dart';
import '../widgets/dictation_toolbar.dart';
import '../widgets/dictation_progress.dart';
import '../widgets/answer_review_dialog.dart';
import '../widgets/completion_dialog.dart';
import 'dictation_result_screen.dart';

class DictationScreen extends StatefulWidget {
  const DictationScreen({super.key});

  @override
  State<DictationScreen> createState() => _DictationScreenState();
}

class _DictationScreenState extends State<DictationScreen> {
  final GlobalKey<State<HandwritingCanvas>> _canvasKey = GlobalKey();
  bool _isSubmitting = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Consumer2<DictationProvider, AppStateProvider>(
        builder: (context, dictationProvider, appState, child) {
          if (dictationProvider.state == DictationState.idle) {
            return _buildIdleState();
          }

          if (dictationProvider.state == DictationState.completed) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _navigateToResultScreen(dictationProvider);
            });
          }

          return _buildDictationInterface(dictationProvider, appState);
        },
      ),
    );
  }

  Widget _buildIdleState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.edit_note,
            size: 64,
            color: Colors.grey,
          ),
          SizedBox(height: 16),
          Text(
            '请先导入单词文件开始默写',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDictationInterface(DictationProvider provider, AppStateProvider appState) {
    final currentWord = provider.currentWord;
    if (currentWord == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        // Progress bar
        DictationProgress(
          current: provider.currentIndex + 1,
          total: provider.totalWords,
          correct: provider.correctCount,
          incorrect: provider.incorrectCount,
        ),
        
        // Main content
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Prompt section
                _buildPromptSection(provider, currentWord),
                
                const SizedBox(height: 16),
                
                // Canvas section
                Expanded(
                  child: _buildCanvasSection(),
                ),
                
                const SizedBox(height: 16),
                
                // Answer section (if in review mode)
                if (provider.state == DictationState.showingAnswer)
                  _buildAnswerSection(currentWord.answer),
                
                const SizedBox(height: 16),
                
                // Control buttons
                _buildControlButtons(provider),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPromptSection(DictationProvider provider, Word currentWord) {
    final session = provider.currentSession;
    final dictationDirection = session?.dictationDirection ?? 0;
    
    // 根据默写方向决定显示内容
    // 0: 原文→译文 (显示prompt，默写answer)
    // 1: 译文→原文 (显示answer，默写prompt)
    final displayText = dictationDirection == 0 ? currentWord.prompt : currentWord.answer;
    
    return Card(
      elevation: 2,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(
              Icons.quiz,
              size: 32,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 12),
            
            // 显示词性和等级信息
            if (currentWord.partOfSpeech != null || currentWord.level != null)
              Wrap(
                spacing: 8,
                children: [
                  if (currentWord.partOfSpeech != null)
                    Chip(
                      label: Text(
                        currentWord.partOfSpeech!,
                        style: const TextStyle(fontSize: 12),
                      ),
                      backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
                    ),
                  if (currentWord.level != null)
                    Chip(
                      label: Text(
                        currentWord.level!,
                        style: const TextStyle(fontSize: 12),
                      ),
                      backgroundColor: Theme.of(context).colorScheme.tertiaryContainer,
                    ),
                ],
              ),
            
            if (currentWord.partOfSpeech != null || currentWord.level != null)
              const SizedBox(height: 12),
            
            Text(
              displayText,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCanvasSection() {
    return Card(
      elevation: 2,
      child: Column(
        children: [
          // Toolbar
          DictationToolbar(
            canvasKey: _canvasKey,
            onClear: () {
              final canvas = _canvasKey.currentState as dynamic;
              if (canvas != null) {
                canvas.clear();
              }
            },
            onUndo: () {
              final canvas = _canvasKey.currentState as dynamic;
              if (canvas != null) {
                canvas.undo();
              }
            },
          ),
          
          // Canvas
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: HandwritingCanvas(
                key: _canvasKey,
                backgroundColor: Theme.of(context).colorScheme.surface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnswerSection(String answer) {
    return Card(
      elevation: 2,
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(
              Icons.lightbulb,
              size: 32,
              color: Theme.of(context).colorScheme.onSecondaryContainer,
            ),
            const SizedBox(height: 12),
            Text(
              '正确答案：',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSecondaryContainer,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              answer,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSecondaryContainer,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlButtons(DictationProvider provider) {
    if (provider.state == DictationState.inProgress) {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _showExitConfirmation(provider),
              icon: const Icon(Icons.exit_to_app),
              label: const Text('退出默写'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              onPressed: _isSubmitting ? null : () => _submitAnswer(provider),
              icon: _isSubmitting 
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: Text(_isSubmitting ? '提交中...' : '提交答案'),
            ),
          ),
        ],
      );
    } else if (provider.state == DictationState.showingAnswer) {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _markIncorrect(provider),
              icon: const Icon(Icons.close),
              label: const Text('错误'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => _markCorrect(provider),
              icon: const Icon(Icons.check),
              label: const Text('正确'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      );
    }

    return const SizedBox.shrink();
  }

  Future<void> _submitAnswer(DictationProvider provider) async {
    setState(() {
      _isSubmitting = true;
    });

    try {
      // Save canvas image
      String? imagePath;
       final canvas = _canvasKey.currentState as dynamic;
       if (canvas != null) {
         imagePath = await canvas.saveAsImage('dictation_${DateTime.now().millisecondsSinceEpoch}.png');
       }
      
      if (imagePath != null) {
        provider.setOriginalImagePath(imagePath);
        await provider.submitAnswer();
      } else {
        throw Exception('保存手写内容失败');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('提交失败: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Future<void> _markCorrect(DictationProvider provider) async {
    await provider.recordResult(true);
    _nextWord(provider);
  }

  Future<void> _markIncorrect(DictationProvider provider) async {
    await provider.recordResult(false);
    _nextWord(provider);
  }

  void _nextWord(DictationProvider provider) {
    (_canvasKey.currentState as dynamic)?.clear();
    provider.nextWord();
  }

  void _showExitConfirmation(DictationProvider provider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认退出'),
        content: const Text('确定要退出当前默写吗？进度将会保存。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _exitDictation(provider);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _exitDictation(DictationProvider provider) {
    final appState = context.read<AppStateProvider>();
    provider.finishSession();
    appState.exitDictationMode();
  }

  void _navigateToResultScreen(DictationProvider provider) async {
    final session = provider.currentSession!;
    final results = provider.results;
    
    // Navigate to result screen
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => DictationResultScreen(
          session: session,
          results: results,
        ),
      ),
    );
    
    // Clean up the dictation state after navigation
    provider.finishSession();
  }

  void _showCompletionDialog(DictationProvider provider) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => CompletionDialog(
        session: provider.currentSession!,
        onRetryIncorrect: () {
          Navigator.of(context).pop();
          _retryIncorrectWords(provider);
        },
        onFinish: () {
          Navigator.of(context).pop();
          _exitDictation(provider);
        },
      ),
    );
  }

  void _retryIncorrectWords(DictationProvider provider) {
    provider.retryIncorrectWords();
  }
}