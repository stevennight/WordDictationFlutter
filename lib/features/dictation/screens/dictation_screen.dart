import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../shared/models/dictation_session.dart';
import '../../../shared/models/word.dart';
import '../../../shared/providers/dictation_provider.dart';
import '../../../shared/providers/app_state_provider.dart';
import '../../../shared/widgets/handwriting_canvas.dart';
import '../../../shared/widgets/unified_canvas_toolbar.dart';
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
  bool _isMarking = false; // 防抖标志，防止重复点击批改按钮

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Consumer2<DictationProvider, AppStateProvider>(
        builder: (context, dictationProvider, appState, child) {
          if (dictationProvider.state == DictationState.idle) {
            return _buildIdleState();
          }

          if (dictationProvider.state == DictationState.error) {
            return _buildErrorState(dictationProvider);
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

  Widget _buildErrorState(DictationProvider provider) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              '默写出现错误',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              provider.errorMessage ?? '未知错误',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton(
                  onPressed: () {
                    provider.clearError();
                    Navigator.of(context).pop();
                  },
                  child: const Text('返回'),
                ),
                const SizedBox(width: 16),
                ElevatedButton(
                  onPressed: () {
                    provider.clearError();
                  },
                  child: const Text('重试'),
                ),
              ],
            ),
          ],
        ),
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
                // Prompt section (now includes answer when showing)
                _buildPromptSection(),
                
                const SizedBox(height: 16),
                
                // Canvas section
                Expanded(
                  child: _buildCanvasSection(),
                ),
                
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

  Widget _buildPromptSection() {
    final provider = context.watch<DictationProvider>();
    final currentWord = provider.currentWord!;
    
    final displayText = provider.currentPromptText;
    final answerText = provider.currentAnswerText;
    
    return Card(
      elevation: 2,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // 词性和等级信息行
            Row(
              children: [
                Icon(
                  Icons.quiz,
                  size: 24,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                
                // 显示词性和等级信息
                if (currentWord.partOfSpeech != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      currentWord.partOfSpeech!,
                      style: const TextStyle(fontSize: 10),
                    ),
                  ),
                
                if (currentWord.partOfSpeech != null && currentWord.level != null)
                  const SizedBox(width: 8),
                  
                if (currentWord.level != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.tertiaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      currentWord.level!,
                      style: const TextStyle(fontSize: 10),
                    ),
                  ),
              ],
            ),
            
            const SizedBox(height: 12),
            
            // 提示内容和答案行
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 提示内容（可点击全屏显示）
                Expanded(
                  flex: 3,
                  child: GestureDetector(
                    onTap: () => _showFullScreenText(displayText, provider.dictationDirection),
                    child: Text(
                      displayText,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ),
                
                // 答案显示（如果在批改模式）
                if (answerText != null) ...[  
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: GestureDetector(
                      onTap: () => _showAnswerFullscreen(answerText, provider.dictationDirection),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.green.withOpacity(0.3),
                            width: 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              answerText,
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.green.shade700,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCanvasSection() {
    final provider = context.read<DictationProvider>();
    
    return Card(
      elevation: 2,
      child: Column(
        children: [
          // 统一工具栏
          UnifiedCanvasToolbar(
            canvasKey: _canvasKey,
            isDictationMode: true,
            showDictationControls: true,
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
                isAnnotationMode: provider.isAnnotationMode,
                backgroundImagePath: provider.isAnnotationMode ? provider.originalImagePath : null,
              ),
            ),
          ),
        ],
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
    } else if (provider.state == DictationState.showingAnswer || provider.state == DictationState.judging) {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _isMarking ? null : () => _markIncorrect(provider),
              icon: _isMarking 
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.close),
              label: Text(_isMarking ? '处理中...' : '错误'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _isMarking ? null : () => _markCorrect(provider),
              icon: _isMarking 
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: Text(_isMarking ? '处理中...' : '正确'),
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
      // Save original canvas image
      String? imagePath;
      final canvas = _canvasKey.currentState as dynamic;
      if (canvas != null) {
        imagePath = await canvas.saveAsImage('dictation_${DateTime.now().millisecondsSinceEpoch}.png');
      }
      
      if (imagePath != null) {
        // 保存原始画板路径
        provider.setOriginalImagePath(imagePath);
        
        // 提交答案
        await provider.submitAnswer();
        
        // 清空画板准备批改
        if (canvas != null) {
          canvas.clearCanvas();
        }
        
        // 进入批改模式
        provider.enterAnnotationMode();
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
    if (_isMarking) return; // 防抖：如果正在处理，直接返回
    
    setState(() {
      _isMarking = true;
    });

    try {
      // 保存批改后的画板
      await _saveAnnotatedImage(provider);
      await provider.recordResult(true);
      // recordResult already calls _showNextWord, no need to call nextWord again
      (_canvasKey.currentState as dynamic)?.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('标记正确失败: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isMarking = false;
        });
      }
    }
  }

  Future<void> _markIncorrect(DictationProvider provider) async {
    if (_isMarking) return; // 防抖：如果正在处理，直接返回
    
    setState(() {
      _isMarking = true;
    });

    try {
      // 保存批改后的画板
      await _saveAnnotatedImage(provider);
      await provider.recordResult(false);
      // recordResult already calls _showNextWord, no need to call nextWord again
      (_canvasKey.currentState as dynamic)?.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('标记错误失败: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isMarking = false;
        });
      }
    }
  }

  Future<void> _saveAnnotatedImage(DictationProvider provider) async {
    try {
      final canvas = _canvasKey.currentState as dynamic;
      if (canvas != null) {
        final imagePath = await canvas.saveAsImage('annotated_${DateTime.now().millisecondsSinceEpoch}.png');
        if (imagePath != null) {
          provider.setAnnotatedImagePath(imagePath);
        }
      }
    } catch (e) {
      // 批改图片保存失败不影响主流程
      debugPrint('保存批改图片失败: $e');
    }
  }

  void _nextWord(DictationProvider provider) {
    // 清空画板
    final canvas = _canvasKey.currentState as dynamic;
    if (canvas != null) {
      canvas.clear();
    }
    
    // 重置批改模式状态
    if (provider.isAnnotationMode) {
      provider.setOriginalImagePath(null);
      provider.setAnnotatedImagePath(null);
    }
    
    // 重置画笔颜色为黑色
    if (canvas != null) {
      canvas.setStrokeColor(Colors.black);
    }
    
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

  void _exitDictation(DictationProvider provider) async {
    final appState = context.read<AppStateProvider>();
    await provider.endSession(); // 调用endSession保存进度
    
    // 如果有结果且状态为completed，导航到结果页面
    if (provider.state == DictationState.completed && provider.results.isNotEmpty) {
      _navigateToResultScreen(provider);
    } else {
      // 否则直接退出
      provider.finishSession();
      appState.exitDictationMode();
    }
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

  void _showAnswerFullscreen(String answerText, int dictationDirection) {
    // 根据默写方向确定标题
    final title = dictationDirection == 0 ? '正确译文' : '正确原文';
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
                          title,
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            color: Colors.green.shade700,
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
                        color: Colors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.green.withOpacity(0.3),
                          width: 2,
                        ),
                      ),
                      child: Text(
                        answerText,
                        style: Theme.of(context).textTheme.displaySmall?.copyWith(
                          color: Colors.green.shade700,
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

  void _showFullScreenText(String text, int dictationDirection) {
    // 根据默写方向确定标题
    final title = dictationDirection == 0 ? '原文内容' : '译文内容';
    
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.8),
      builder: (context) => GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            margin: const EdgeInsets.all(20),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
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
                      title,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
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
                    color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                      width: 2,
                    ),
                  ),
                  child: Text(
                    text,
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
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
    );
  }
}