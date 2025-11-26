import 'dart:math' as Math;
import 'package:flutter/material.dart';
import 'package:flutter_word_dictation/core/services/word_explanation_batch_service.dart';
import 'package:flutter_word_dictation/shared/models/word.dart';

/// AI批量生成进度对话框
class AIBatchProgressDialog extends StatefulWidget {
  final String title;
  final VoidCallback? onCancel;
  final bool showRetryButton;
  final Function(List<Word>)? onRetryAll;
  final Function(Word)? onRetrySingle;

  const AIBatchProgressDialog({
    Key? key,
    required this.title,
    this.onCancel,
    this.showRetryButton = false,
    this.onRetryAll,
    this.onRetrySingle,
  }) : super(key: key);

  @override
  State<AIBatchProgressDialog> createState() => _AIBatchProgressDialogState();
}

class _AIBatchProgressDialogState extends State<AIBatchProgressDialog> {
  String _currentStep = '准备生成...';
  double _progress = 0.0;
  int _currentIndex = 0;
  int _totalCount = 0;
  int _skippedCount = 0;
  int _succeededCount = 0;
  int _failedCount = 0;
  bool _isIndeterminate = true;
  WordExplanationDetailedStatus? _detailedStatus;
  List<WordProgressItem> _wordProgressItems = [];
  bool _showDetails = true; // 默认展开详情列表
  bool _isCompleted = false;
  List<Word> _failedWords = [];
  int _currentPage = 0;
  static const int _itemsPerPage = 20;

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // 防止用户意外关闭对话框
        if (widget.onCancel != null) {
          widget.onCancel!();
          return true;
        }
        return false;
      },
      child: AlertDialog(
        title: Row(
          children: [
            Expanded(child: Text(widget.title)),
            IconButton(
              icon: Icon(_showDetails ? Icons.expand_less : Icons.expand_more),
              onPressed: () {
                setState(() {
                  _showDetails = !_showDetails;
                });
              },
              tooltip: _showDetails ? '收起详情' : '显示详情',
            ),
          ],
        ),
        content: SizedBox(
          width: Math.max(300, MediaQuery.of(context).size.width * 0.8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 当前状态
              _buildCurrentStatus(),
              const SizedBox(height: 16),
              
              // 进度条
              _buildProgressBar(),
              const SizedBox(height: 8),
              
              // 统计信息
              _buildStatistics(),
              
              // 详细单词列表
              if (_showDetails) ...[
                const SizedBox(height: 16),
                _buildWordDetails(),
              ],
            ],
          ),
        ),
        actions: _buildActions(),
      ),
    );
  }

  Widget _buildCurrentStatus() {
    String statusText = _currentStep;
    if (_detailedStatus != null) {
      statusText = '${_detailedStatus!.displayName} - $_currentStep';
    }
    
    return Text(
      statusText,
      style: const TextStyle(fontSize: 16),
    );
  }

  Widget _buildProgressBar() {
    if (_isIndeterminate) {
      return const LinearProgressIndicator();
    } else {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinearProgressIndicator(value: _progress),
          const SizedBox(height: 4),
          Text(
            '$_currentIndex / $_totalCount',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
        ],
      );
    }
  }

  Widget _buildStatistics() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _buildStatItem('跳过', _skippedCount, Colors.orange),
        _buildStatItem('成功', _succeededCount, Colors.green),
        _buildStatItem('失败', _failedCount, Colors.red),
      ],
    );
  }

  Widget _buildStatItem(String label, int count, Color color) {
    return Column(
      children: [
        Text(
          count.toString(),
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildWordDetails() {
    if (_wordProgressItems.isEmpty) {
      return const Text('暂无处理记录', style: TextStyle(color: Colors.grey));
    }

    // 按状态排序：processing -> pending -> failed -> succeeded/skipped
    final sortedItems = _getSortedWordProgressItems();
    final totalPages = (sortedItems.length / _itemsPerPage).ceil();
    final startIndex = _currentPage * _itemsPerPage;
    final endIndex = Math.min(startIndex + _itemsPerPage, sortedItems.length);
    final currentPageItems = sortedItems.sublist(startIndex, endIndex);

    return Column(
      children: [
        // 状态统计行
        _buildStatusSummary(sortedItems),
        const SizedBox(height: 8),
        
        // 列表
        Container(
          height: 200,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey[300]!),
            borderRadius: BorderRadius.circular(4),
          ),
          child: ListView.builder(
            itemCount: currentPageItems.length,
            itemBuilder: (context, index) {
              final item = currentPageItems[index];
              return _buildWordProgressItem(item);
            },
          ),
        ),
        
        // 分页控制
        if (totalPages > 1) ...[
          const SizedBox(height: 8),
          _buildPaginationControls(totalPages, sortedItems.length),
        ],
      ],
    );
  }

  /// 获取排序后的单词进度列表
  List<WordProgressItem> _getSortedWordProgressItems() {
    final items = List<WordProgressItem>.from(_wordProgressItems);
    items.sort((a, b) {
      // 状态优先级：processing(0) -> pending(1) -> failed(2) -> succeeded/skipped(3)
      int getPriority(String status) {
        switch (status) {
          case 'processing':
            return 0;
          case 'pending':
            return 1;
          case 'failed':
            return 2;
          case 'succeeded':
          case 'skipped':
            return 3;
          default:
            return 4;
        }
      }
      
      final priorityA = getPriority(a.status);
      final priorityB = getPriority(b.status);
      
      if (priorityA != priorityB) {
        return priorityA.compareTo(priorityB);
      }
      
      // 相同状态下，按照添加顺序（保持原有顺序）
      return _wordProgressItems.indexOf(a).compareTo(_wordProgressItems.indexOf(b));
    });
    return items;
  }

  /// 构建状态统计摘要
  Widget _buildStatusSummary(List<WordProgressItem> sortedItems) {
    final processingCount = sortedItems.where((item) => item.status == 'processing').length;
    final pendingCount = sortedItems.where((item) => item.status == 'pending').length;
    final failedCount = sortedItems.where((item) => item.status == 'failed').length;
    final succeededCount = sortedItems.where((item) => item.status == 'succeeded' || item.status == 'skipped').length;
    
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _buildMiniStatItem('处理中', processingCount, Colors.blue),
        _buildMiniStatItem('队列中', pendingCount, Colors.grey),
        _buildMiniStatItem('失败', failedCount, Colors.red),
        _buildMiniStatItem('完成', succeededCount, Colors.green),
      ],
    );
  }

  Widget _buildMiniStatItem(String label, int count, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '$label: $count',
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey[700],
          ),
        ),
      ],
    );
  }

  /// 构建分页控制器
  Widget _buildPaginationControls(int totalPages, int totalItems) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left, size: 20),
          onPressed: _currentPage > 0
              ? () {
                  setState(() {
                    _currentPage--;
                  });
                }
              : null,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
        const SizedBox(width: 12),
        Text(
          '第 ${_currentPage + 1} / $totalPages 页 (共 $totalItems 项)',
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[700],
          ),
        ),
        const SizedBox(width: 12),
        IconButton(
          icon: const Icon(Icons.chevron_right, size: 20),
          onPressed: _currentPage < totalPages - 1
              ? () {
                  setState(() {
                    _currentPage++;
                  });
                }
              : null,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
      ],
    );
  }

  Widget _buildWordProgressItem(WordProgressItem item) {
    Color statusColor;
    IconData statusIcon;
    
    switch (item.status) {
      case 'pending':
        statusColor = Colors.grey;
        statusIcon = Icons.radio_button_unchecked;
        break;
      case 'skipped':
        statusColor = Colors.orange;
        statusIcon = Icons.skip_next;
        break;
      case 'succeeded':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        break;
      case 'failed':
        statusColor = Colors.red;
        statusIcon = Icons.error;
        break;
      case 'processing':
      default:
        statusColor = Colors.blue;
        statusIcon = Icons.hourglass_empty;
        break;
    }

    return ListTile(
      dense: true,
      leading: Icon(statusIcon, color: statusColor, size: 20),
      title: Text(
        '${item.word.prompt} - ${item.word.answer}',
        style: const TextStyle(fontSize: 14),
      ),
      subtitle: item.detailedStatus != null
          ? Text(
              item.detailedStatus!.displayName,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            )
          : null,
      trailing: item.status == 'failed' && _isCompleted
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (item.errorMessage != null)
                  IconButton(
                    icon: const Icon(Icons.info_outline, size: 16),
                    onPressed: () => _showErrorDetails(item),
                    tooltip: '查看错误信息',
                  ),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 16),
                  onPressed: () => _retrySingleWord(item.word),
                  tooltip: '重试此单词',
                ),
              ],
            )
          : item.errorMessage != null
              ? IconButton(
                  icon: const Icon(Icons.info_outline, size: 16),
                  onPressed: () => _showErrorDetails(item),
                  tooltip: '查看错误信息',
                )
              : null,
    );
  }

  List<Widget> _buildActions() {
    List<Widget> actions = [];
    
    if (_isCompleted) {
      // 完成后显示重试和关闭按钮
      if (widget.showRetryButton && _failedCount > 0) {
        actions.add(
          TextButton.icon(
            onPressed: () => _retryFailedWords(),
            icon: const Icon(Icons.refresh),
            label: Text('重试全部失败($_failedCount)'),
          ),
        );
      }
      actions.add(
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      );
    } else {
      // 处理中显示中断按钮（始终显示）
      actions.add(
        TextButton(
          onPressed: widget.onCancel,
          child: const Text('中断'),
        ),
      );
    }
    
    return actions;
  }

  void _retryFailedWords() {
    if (widget.onRetryAll != null && _failedWords.isNotEmpty) {
      widget.onRetryAll!(_failedWords);
    }
  }

  void _retrySingleWord(Word word) {
    if (widget.onRetrySingle != null) {
      widget.onRetrySingle!(word);
    }
  }

  void _showErrorDetails(WordProgressItem item) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${item.word.prompt} 错误详情'),
        content: SingleChildScrollView(
          child: Text(
            item.errorMessage ?? '未知错误',
            style: const TextStyle(fontSize: 14),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  /// 更新进度步骤
  void updateStep(String step) {
    if (mounted) {
      setState(() {
        _currentStep = step;
        _isIndeterminate = true;
      });
    }
  }

  /// 更新详细状态
  void updateDetailedStatus(WordExplanationDetailedStatus status) {
    if (mounted) {
      setState(() {
        _detailedStatus = status;
      });
    }
  }

  /// 更新进度值
  void updateProgress(WordExplanationProgress progress) {
    if (mounted) {
      setState(() {
        _currentStep = '正在处理: ${progress.word.prompt}';
        _currentIndex = progress.current;
        _totalCount = progress.total;
        _skippedCount = progress.skippedExisting;
        _succeededCount = progress.succeeded;
        _failedCount = progress.failed;
        _progress = progress.total > 0 ? progress.current / progress.total : 0.0;
        _isIndeterminate = false;
        _detailedStatus = progress.detailedStatus;

        // 更新单词进度列表
        final existingIndex = _wordProgressItems.indexWhere(
          (item) => item.word.id == progress.word.id,
        );
        
        final progressItem = WordProgressItem(
          word: progress.word,
          status: progress.status,
          detailedStatus: progress.detailedStatus,
          errorMessage: progress.errorMessage,
        );

        if (existingIndex >= 0) {
          _wordProgressItems[existingIndex] = progressItem;
        } else {
          _wordProgressItems.add(progressItem);
        }

        // 收集失败的单词
        if (progress.status == 'failed') {
          if (!_failedWords.any((w) => w.id == progress.word.id)) {
            _failedWords.add(progress.word);
          }
        }
        
        // 当开始处理新单词时，自动跳转到第一页以显示正在处理的单词
        if (progress.status == 'processing' && _currentPage > 0) {
          _currentPage = 0;
        }
      });
    }
  }

  /// 设置为不确定进度
  void setIndeterminate({String? step}) {
    if (mounted) {
      setState(() {
        if (step != null) {
          _currentStep = step;
        }
        _isIndeterminate = true;
      });
    }
  }

  /// 完成时显示最终结果
  void showCompletionResult() {
    if (mounted) {
      setState(() {
        _currentStep = '生成完成';
        _isIndeterminate = false;
        _detailedStatus = WordExplanationDetailedStatus.completed;
        _isCompleted = true;
      });
    }
  }
}

/// 单词进度项
class WordProgressItem {
  final Word word;
  final String status;
  final WordExplanationDetailedStatus? detailedStatus;
  final String? errorMessage;

  WordProgressItem({
    required this.word,
    required this.status,
    this.detailedStatus,
    this.errorMessage,
  });
}

/// 显示AI批量生成进度对话框的辅助方法
Future<List<Word>?> showAIBatchProgressDialog({
  required BuildContext context,
  required String title,
  required Future<WordExplanationBatchSummary> Function({
    void Function(WordExplanationProgress)? onProgress,
    void Function(WordExplanationDetailedStatus)? onDetailedProgress,
    bool Function()? isCancelled,
  }) generateFunction,
  VoidCallback? onCancel,
  bool enableRetry = true,
  Future<void> Function(List<Word>)? onRetryAll,
  Future<void> Function(Word)? onRetrySingle,
}) async {
  final GlobalKey<_AIBatchProgressDialogState> dialogKey = GlobalKey<_AIBatchProgressDialogState>();
  bool isCancelled = false;

  // 显示对话框
  showDialog<List<Word>>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      return AIBatchProgressDialog(
        key: dialogKey,
        title: title,
        onCancel: () {
          // 中断：设置标志，停止后续处理，但不关闭对话框
          isCancelled = true;
          if (dialogKey.currentState != null && dialogKey.currentState!.mounted) {
            dialogKey.currentState!.updateStep('停止中...');
          }
          onCancel?.call();
        },
        showRetryButton: enableRetry,
        onRetryAll: onRetryAll != null
            ? (words) {
                Navigator.of(context).pop();
                onRetryAll(words);
              }
            : null,
        onRetrySingle: onRetrySingle != null
            ? (word) {
                Navigator.of(context).pop();
                onRetrySingle(word);
              }
            : null,
      );
    },
  );

  // 执行生成操作
  try {
    final result = await generateFunction(
      onProgress: (progress) {
        if (isCancelled) return;
        if (dialogKey.currentState != null && dialogKey.currentState!.mounted) {
          dialogKey.currentState!.updateProgress(progress);
          WidgetsBinding.instance.scheduleFrame();
        }
      },
      onDetailedProgress: (status) {
        if (isCancelled) return;
        if (dialogKey.currentState != null && dialogKey.currentState!.mounted) {
          dialogKey.currentState!.updateDetailedStatus(status);
          WidgetsBinding.instance.scheduleFrame();
        }
      },
      isCancelled: () => isCancelled,
    );

    // 显示完成结果（不关闭对话框，让用户可以查看详情和重试）
    if (dialogKey.currentState != null && dialogKey.currentState!.mounted) {
      if (isCancelled) {
        dialogKey.currentState!.updateStep('已中断');
      }
      dialogKey.currentState!.showCompletionResult();
    }

    // 返回失败的单词列表（如果有的话）
    return result.failedWords;
  } catch (e) {
    // 关闭对话框并重新抛出异常
    if (context.mounted && !isCancelled) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    rethrow;
  }
}
