import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../shared/models/dictation_result.dart';
import '../../../shared/models/dictation_session.dart';
import '../../../shared/providers/history_provider.dart';
import '../widgets/result_detail_card.dart';

class HistoryDetailScreen extends StatefulWidget {
  final String sessionId;

  const HistoryDetailScreen({
    super.key,
    required this.sessionId,
  });

  @override
  State<HistoryDetailScreen> createState() => _HistoryDetailScreenState();
}

class _HistoryDetailScreenState extends State<HistoryDetailScreen> {
  DictationSession? _session;
  List<DictationResult> _results = [];
  List<DictationResult> _filteredResults = [];
  bool _isLoading = true;
  String? _error;
  bool _showOnlyErrors = false;

  @override
  void initState() {
    super.initState();
    _loadSessionDetails();
  }

  Future<void> _loadSessionDetails() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final historyProvider = context.read<HistoryProvider>();
      final session = await historyProvider.getSession(widget.sessionId);
      final results = await historyProvider.getSessionResults(widget.sessionId);

      if (mounted) {
        setState(() {
          _session = session;
          _results = results;
          _filteredResults = _getFilteredResults();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '加载详情失败: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('默写详情'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_error != null) {
      return Center(
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
              _error!,
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadSessionDetails,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (_session == null) {
      return const Center(
        child: Text('会话不存在'),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSessionSummary(),
          const SizedBox(height: 16),
          _buildResultsList(),
        ],
      ),
    );
  }

  Widget _buildSessionSummary() {
    final session = _session!;
    final accuracy = session.accuracy;
    final duration = session.duration;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.summarize,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  '会话概要',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            _buildSummaryRow('文件名', session.wordFileName ?? '未知'),
            _buildSummaryRow('开始时间', DateFormat('yyyy-MM-dd HH:mm:ss').format(session.startTime)),
            if (session.endTime != null)
              _buildSummaryRow('结束时间', DateFormat('yyyy-MM-dd HH:mm:ss').format(session.endTime!)),
            _buildSummaryRow('模式', _getModeText(session.mode)),
            _buildSummaryRow('默写方向', _getDirectionText(session.dictationDirection)),
            _buildSummaryRow('状态', _getStatusText(session)),
            if (duration != null)
              _buildSummaryRow('用时', '${duration.inMinutes}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}'),
            
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 12),
            
            // Statistics
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    '总题数',
                    session.totalWords.toString(),
                    Icons.quiz,
                    Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildStatCard(
                    '正确',
                    session.correctCount.toString(),
                    Icons.check_circle,
                    Colors.green,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildStatCard(
                    '错误',
                    session.incorrectCount.toString(),
                    Icons.cancel,
                    Colors.red,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildStatCard(
                    '准确率',
                    '${accuracy.toInt()}%',
                    Icons.percent,
                    _getAccuracyColor(accuracy),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const Text(': '),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: color.withOpacity(0.3),
        ),
      ),
      child: Column(
        children: [
          Icon(
            icon,
            color: color,
            size: 20,
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildResultsList() {
    if (_results.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: Column(
              children: [
                Icon(
                  Icons.inbox,
                  size: 48,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 16),
                Text(
                  '暂无详细结果',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.list,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text(
              '详细结果',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            // 过滤按钮
            OutlinedButton.icon(
              onPressed: _toggleErrorFilter,
              icon: Icon(
                _showOnlyErrors ? Icons.filter_alt : Icons.filter_alt_outlined,
                size: 18,
              ),
              label: Text(
                _showOnlyErrors ? '仅错误' : '全部',
                style: const TextStyle(fontSize: 12),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '共 ${_filteredResults.length} 题',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _filteredResults.length,
          separatorBuilder: (context, index) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final result = _filteredResults[index];
            return ResultDetailCard(
              result: result,
              index: index + 1,
              dictationDirection: _session?.dictationDirection ?? 0,
            );
          },
        ),
      ],
    );
  }

  String _getModeText(DictationMode mode) {
    switch (mode) {
      case DictationMode.sequential:
        return '顺序默写';
      case DictationMode.random:
        return '随机默写';
      case DictationMode.retry:
        return '重做错题';
    }
  }

  Color _getAccuracyColor(double accuracy) {
    if (accuracy >= 0.9) {
      return Colors.green;
    } else if (accuracy >= 0.7) {
      return Colors.orange;
    } else {
      return Colors.red;
    }
  }

  List<DictationResult> _getFilteredResults() {
    if (_showOnlyErrors) {
      return _results.where((result) => !result.isCorrect).toList();
    }
    return _results;
  }

  void _toggleErrorFilter() {
    setState(() {
      _showOnlyErrors = !_showOnlyErrors;
      _filteredResults = _getFilteredResults();
    });
  }
  
  String _getStatusText(DictationSession session) {
    switch (session.status) {
      case SessionStatus.completed:
        return '已完成';
      case SessionStatus.incomplete:
        // 使用expectedTotalWords显示预期数量，totalWords显示实际完成数量
        final expectedTotal = session.expectedTotalWords ?? session.totalWords;
        return '未完成 (${session.correctCount + session.incorrectCount}/$expectedTotal)';
      case SessionStatus.inProgress:
        return '进行中';
      case SessionStatus.paused:
        return '已暂停';
      }
  }

  String _getDirectionText(int direction) {
    switch (direction) {
      case 0:
        return '原文 → 译文';
      case 1:
        return '译文 → 原文';
      default:
        return '未知方向';
    }
  }
}