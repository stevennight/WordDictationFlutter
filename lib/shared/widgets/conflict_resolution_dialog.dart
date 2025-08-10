import 'package:flutter/material.dart';
import '../../core/services/session_conflict_resolver.dart';
import '../../shared/models/dictation_session.dart';
import 'package:intl/intl.dart';

/// 冲突解决选择对话框
class ConflictResolutionDialog extends StatefulWidget {
  final List<SessionConflict> conflicts;
  
  const ConflictResolutionDialog({
    super.key,
    required this.conflicts,
  });
  
  @override
  State<ConflictResolutionDialog> createState() => _ConflictResolutionDialogState();
}

class _ConflictResolutionDialogState extends State<ConflictResolutionDialog> {
  final Map<String, ConflictResolution> _userChoices = {};
  
  @override
  void initState() {
    super.initState();
    // 初始化所有冲突的选择为使用远端数据
    for (final conflict in widget.conflicts) {
      _userChoices[conflict.sessionId] = ConflictResolution.useRemote;
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('解决同步冲突 (${widget.conflicts.length}个)'),
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.8,
        height: MediaQuery.of(context).size.height * 0.6,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '发现以下会话存在冲突，请选择保留哪个版本：',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              ...widget.conflicts.map((conflict) => _buildConflictItem(conflict)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(_userChoices),
          child: const Text('确定'),
        ),
      ],
    );
  }
  
  Widget _buildConflictItem(SessionConflict conflict) {
    final dateFormat = DateFormat('yyyy-MM-dd HH:mm');
    
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 冲突原因
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                conflict.reason,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
            ),
            const SizedBox(height: 12),
            
            // 本地和远端数据对比
            Row(
              children: [
                // 本地数据
                Expanded(
                  child: _buildSessionCard(
                    context,
                    '本地数据',
                    conflict.localSession,
                    dateFormat,
                    isSelected: _userChoices[conflict.sessionId] == ConflictResolution.useLocal,
                    onTap: () {
                      setState(() {
                        _userChoices[conflict.sessionId] = ConflictResolution.useLocal;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 12),
                // 远端数据
                Expanded(
                  child: _buildSessionCard(
                    context,
                    '云端数据',
                    conflict.remoteSession,
                    dateFormat,
                    isSelected: _userChoices[conflict.sessionId] == ConflictResolution.useRemote,
                    onTap: () {
                      setState(() {
                        _userChoices[conflict.sessionId] = ConflictResolution.useRemote;
                      });
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildSessionCard(
    BuildContext context,
    String title,
    DictationSession? session,
    DateFormat dateFormat,
    {
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected 
                ? Theme.of(context).colorScheme.primary 
                : Theme.of(context).colorScheme.outline,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
          color: isSelected 
              ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3)
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题和选择指示器
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isSelected 
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                  ),
                ),
                if (isSelected)
                  Icon(
                    Icons.check_circle,
                    color: Theme.of(context).colorScheme.primary,
                    size: 20,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            
            if (session == null) ...[
              // 远端不存在的情况
              Text(
                '此会话在云端不存在',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ] else ...[
              // 会话基本信息
              _buildInfoRow('词书', session.wordFileName ?? '未知'),
              _buildInfoRow('模式', _getModeText(session.mode)),
              _buildInfoRow('状态', _getStatusText(session.status)),
              _buildInfoRow('开始时间', dateFormat.format(session.startTime)),
              
              if (session.endTime != null)
                _buildInfoRow('结束时间', dateFormat.format(session.endTime!)),
              
              _buildInfoRow('总词数', '${session.totalWords}'),
              _buildInfoRow('正确数', '${session.correctCount}'),
              _buildInfoRow('错误数', '${session.incorrectCount}'),
              
              // 删除状态特殊处理
              if (session.deleted) ...[
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.delete,
                        size: 14,
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '已删除',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                      ),
                    ],
                  ),
                ),
                if (session.deletedAt != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '删除时间: ${dateFormat.format(session.deletedAt!)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ),
              ],
            ],
          ],
        ),
      ),
    );
  }
  
  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60,
            child: Text(
              '$label:',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 11,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  String _getModeText(DictationMode mode) {
    switch (mode) {
      case DictationMode.sequential:
        return '顺序';
      case DictationMode.random:
        return '随机';
      case DictationMode.retry:
        return '重做';
    }
  }
  
  String _getStatusText(SessionStatus status) {
    switch (status) {
      case SessionStatus.inProgress:
        return '进行中';
      case SessionStatus.completed:
        return '已完成';
      case SessionStatus.paused:
        return '已暂停';
      case SessionStatus.incomplete:
        return '未完成';
    }
  }
}

/// 显示冲突解决对话框
Future<Map<String, ConflictResolution>?> showConflictResolutionDialog(
  BuildContext context,
  List<SessionConflict> conflicts,
) {
  return showDialog<Map<String, ConflictResolution>>(
    context: context,
    barrierDismissible: false, // 不允许点击外部关闭
    builder: (context) => ConflictResolutionDialog(conflicts: conflicts),
  );
}