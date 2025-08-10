import 'package:flutter/material.dart';

/// 同步进度对话框
class SyncProgressDialog extends StatefulWidget {
  final String title;
  final VoidCallback? onCancel;

  const SyncProgressDialog({
    Key? key,
    required this.title,
    this.onCancel,
  }) : super(key: key);

  @override
  State<SyncProgressDialog> createState() => _SyncProgressDialogState();
}

class _SyncProgressDialogState extends State<SyncProgressDialog> {
  String _currentStep = '准备同步...';
  double _progress = 0.0;
  int _currentIndex = 0;
  int _totalCount = 0;
  bool _isIndeterminate = true;

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
        title: Text(widget.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _currentStep,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            if (_isIndeterminate)
              const LinearProgressIndicator()
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(value: _progress),
                  const SizedBox(height: 8),
                  Text(
                    '$_currentIndex / $_totalCount',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
          ],
        ),
        actions: widget.onCancel != null
            ? [
                TextButton(
                  onPressed: widget.onCancel,
                  child: const Text('取消'),
                ),
              ]
            : null,
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

  /// 更新进度值
  void updateProgress(int current, int total, {String? step}) {
    if (mounted) {
      setState(() {
        if (step != null) {
          _currentStep = step;
        }
        _currentIndex = current;
        _totalCount = total;
        _progress = total > 0 ? current / total : 0.0;
        _isIndeterminate = false;
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
}

/// 进度回调函数类型
typedef ProgressCallback = void Function(String step, {int? current, int? total});

/// 显示同步进度对话框的辅助方法
Future<T?> showSyncProgressDialog<T>({
  required BuildContext context,
  required String title,
  required Future<T> Function(ProgressCallback onProgress) syncFunction,
  VoidCallback? onCancel,
}) async {
  final GlobalKey<_SyncProgressDialogState> dialogKey = GlobalKey<_SyncProgressDialogState>();
  bool isCancelled = false;

  // 显示对话框
  final dialogFuture = showDialog<T>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      return SyncProgressDialog(
        key: dialogKey,
        title: title,
        onCancel: onCancel != null
            ? () {
                isCancelled = true;
                onCancel();
                Navigator.of(context).pop();
              }
            : null,
      );
    },
  );

  // 执行同步操作
  try {
    final result = await syncFunction((step, {current, total}) {
      if (isCancelled) return;
      
      // 直接更新进度，不使用addPostFrameCallback
      if (dialogKey.currentState != null && dialogKey.currentState!.mounted) {
        if (current != null && total != null) {
          dialogKey.currentState!.updateProgress(current, total, step: step);
        } else {
          dialogKey.currentState!.updateStep(step);
        }
        // 强制刷新UI
        WidgetsBinding.instance.scheduleFrame();
      }
    });

    // 关闭对话框并返回结果
    if (context.mounted && !isCancelled) {
      Navigator.of(context, rootNavigator: true).pop(result);
    }
    return result;
  } catch (e) {
    // 关闭对话框并重新抛出异常
    if (context.mounted && !isCancelled) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    rethrow;
  }
}