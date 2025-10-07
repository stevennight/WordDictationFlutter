import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../shared/providers/app_state_provider.dart';
import '../../../shared/providers/dictation_provider.dart';
import '../../../shared/utils/path_utils.dart';
import '../../../shared/widgets/handwriting_canvas.dart';
import '../../../shared/widgets/collapsible_canvas_toolbar.dart';
import '../../../shared/widgets/collapsible_progress_bar.dart';
import 'dictation_result_screen.dart';
import '../../../shared/utils/word_navigation_utils.dart';

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
        // Progress bar - 可收起的进度信息栏
        CollapsibleProgressBar(
          current: provider.currentIndex + 1,
          total: provider.totalWords,
          correct: provider.correctCount,
          incorrect: provider.incorrectCount,
          title: '默写进度',
          onExit: () => _showExitConfirmation(provider),
        ),
        
        // Main content
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Control buttons - 移动到单词上方
                _buildControlButtons(provider),
                
                const SizedBox(height: 16),
                
                // Prompt section (now includes answer when showing)
                _buildPromptSection(),
                
                const SizedBox(height: 16),
                
                // Canvas section
                Expanded(
                  child: _buildCanvasSection(),
                ),
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
                const SizedBox(width: 4),
                // 批改状态下显示详情入口（基于原文文本）
                if (answerText != null)
                  IconButton(
                    onPressed: () {
                      WordNavigationUtils.openWordDetailByText(context, currentWord.prompt);
                    },
                    icon: const Icon(Icons.info_outline, size: 20),
                    tooltip: '单词详情',
                    style: IconButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(24, 24),
                    ),
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
          // 可收起的工具栏
          CollapsibleCanvasToolbar(
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
                backgroundColor: Colors.white,
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
      // 检查当前单词是否已经提交过（有结果记录）
      final hasSubmitted = provider.results.any(
        (result) => result.wordIndex == provider.currentIndex
      );
      
      return Column(
        children: [
          // 主要操作按钮行
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: (provider.currentIndex > 0 && !hasSubmitted && !_isSubmitting) 
                      ? () => _goToPreviousWord(provider) 
                      : null,
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('上一个'),
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
          ),
        ],
      );
    } else if (provider.state == DictationState.showingAnswer || provider.state == DictationState.judging) {
      return Column(
        children: [
          // 在批改状态下不显示返回按钮
          
          // 批改按钮行
          Row(
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
        // 转换为相对路径
        final relativePath = await PathUtils.convertToRelativePath(imagePath);
        
        // 保存原始画板路径（使用相对路径）
        await provider.setOriginalImagePath(relativePath);
        
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
      
      // 检查是否是修改现有结果
      final existingResult = provider.results.where(
        (result) => result.wordIndex == provider.currentIndex
      ).firstOrNull;
      
      if (existingResult != null) {
        // 修改现有结果
        provider.updateResult(
          provider.currentIndex, 
          true, 
          annotatedImagePath: provider.annotatedImagePath
        );
        // 重新批改完成后，自动进入下一个单词
        await Future.delayed(const Duration(milliseconds: 200)); // 延迟确保状态更新
        if (mounted) {
          _nextWord(provider);
        }
      } else {
        // 记录新结果
        await provider.recordResult(true);
      }
      
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
      
      // 检查是否是修改现有结果
      final existingResult = provider.results.where(
        (result) => result.wordIndex == provider.currentIndex
      ).firstOrNull;
      
      if (existingResult != null) {
        // 修改现有结果
        provider.updateResult(
          provider.currentIndex, 
          false, 
          annotatedImagePath: provider.annotatedImagePath
        );
        // 重新批改完成后，自动进入下一个单词
        await Future.delayed(const Duration(milliseconds: 200)); // 延迟确保状态更新
        if (mounted) {
          _nextWord(provider);
        }
      } else {
        // 记录新结果
        await provider.recordResult(false);
      }
      
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
          // 转换为相对路径
          final relativePath = await PathUtils.convertToRelativePath(imagePath);
          await provider.setAnnotatedImagePath(relativePath);
        }
      }
    } catch (e) {
      // 批改图片保存失败不影响主流程
      debugPrint('保存批改图片失败: $e');
    }
  }



  Future<void> _nextWord(DictationProvider provider) async {
    // 清空画板
    final canvas = _canvasKey.currentState as dynamic;
    if (canvas != null) {
      canvas.clear();
    }
    
    // 重置批改模式状态
    if (provider.isAnnotationMode) {
      await provider.setOriginalImagePath(null);
        await provider.setAnnotatedImagePath(null);
    }
    
    // 重置画笔颜色为黑色
    if (canvas != null) {
      canvas.setStrokeColor(Colors.black);
    }
    
    // 检查是否是重新批改场景（当前单词已有结果）
    final hasExistingResult = provider.results.any(
      (result) => result.wordIndex == provider.currentIndex
    );
    
    if (hasExistingResult) {
      // 重新批改后，直接跳转到下一个单词
      provider.goToNextWord();
      // 如果已经是最后一个单词，完成默写
      if (provider.currentIndex >= provider.totalWords - 1) {
        // 这里应该触发完成逻辑，但goToNextWord已经处理了边界
      }
    } else {
      // 正常流程，通过recordResult递增索引
      provider.nextWord();
    }
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

  Future<void> _exitDictation(DictationProvider provider) async {
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

  Future<void> _navigateToResultScreen(DictationProvider provider) async {
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

  Future<void> _goToPreviousWord(DictationProvider provider) async {
    if (provider.currentIndex > 0) {
      // 清除画布
      (_canvasKey.currentState as dynamic)?.clear();
      
      // 返回上一个单词
      provider.goToPreviousWord();
      
      // 检查是否已有该单词的批改结果
      final existingResult = provider.results.where(
        (result) => result.wordIndex == provider.currentIndex
      ).firstOrNull;
      
      if (existingResult != null) {
        // 如果已有结果，进入批改状态并恢复图片，只允许修改批改内容
        await provider.setAnnotatedImagePath(existingResult.annotatedImagePath);
        provider.enterAnnotationMode();
        
        // 恢复画布上的原始图片作为背景
        if (existingResult.originalImagePath != null) {
          // 直接设置原始图片路径，让画布组件自己处理路径转换
          await provider.setOriginalImagePath(existingResult.originalImagePath);
        }
        
        // 如果有批改图片，加载批改图片到画布上
        if (existingResult.annotatedImagePath != null) {
          await _loadImageToCanvas(existingResult.annotatedImagePath!);
        }
      } else {
        // 如果没有结果，允许返回到答题状态（只要下一个单词未提交）
        provider.setState(DictationState.inProgress);
        await provider.setAnnotatedImagePath(null);
        await provider.setOriginalImagePath(null);
      }
    }
  }



  Future<void> _loadImageToCanvas(String imagePath) async {
    try {
      debugPrint('Loading annotated image to canvas: $imagePath');
      
      // 这个方法现在只用于加载批改图片到画布上
      // 背景图片的加载由 HandwritingCanvas 自己处理
      
      // TODO: 实现批改图片的加载逻辑
      // 目前暂时不实现，因为批改图片应该作为笔迹而不是背景
      
    } catch (e) {
      debugPrint('加载批改图片到画布失败: $e');
    }
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