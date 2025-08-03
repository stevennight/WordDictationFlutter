import 'package:flutter/material.dart';

import '../../../shared/models/dictation_session.dart';

class CompletionDialog extends StatelessWidget {
  final DictationSession session;
  final VoidCallback onRetryIncorrect;
  final VoidCallback onFinish;

  const CompletionDialog({
    super.key,
    required this.session,
    required this.onRetryIncorrect,
    required this.onFinish,
  });

  @override
  Widget build(BuildContext context) {
    final accuracy = session.accuracy;
    final duration = session.duration;
    final screenHeight = MediaQuery.of(context).size.height;
    
    return Dialog(
      child: Container(
        constraints: BoxConstraints(
          maxWidth: 400,
          maxHeight: screenHeight * 0.8, // 使用屏幕高度的80%
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _getHeaderColor(context, accuracy),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    _getHeaderIcon(accuracy),
                    size: 48,
                    color: Colors.white,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _getHeaderTitle(accuracy),
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _getHeaderSubtitle(accuracy),
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
            
            // Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    // Statistics
                    _buildStatisticsSection(context),
                    
                    const SizedBox(height: 20),
                    
                    // Performance analysis
                    _buildPerformanceSection(context, accuracy),
                    
                    const SizedBox(height: 20),
                    
                    // Action buttons
                    _buildActionButtons(context),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatisticsSection(BuildContext context) {
    final duration = session.duration;
    final durationText = duration != null
        ? '${duration.inMinutes}分${duration.inSeconds % 60}秒'
        : '未知';
    
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                context,
                icon: Icons.quiz,
                label: '总题数',
                value: session.totalWords.toString(),
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                context,
                icon: Icons.timer,
                label: '用时',
                value: durationText,
                color: Theme.of(context).colorScheme.secondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                context,
                icon: Icons.check_circle,
                label: '正确',
                value: session.correctCount.toString(),
                color: Colors.green,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                context,
                icon: Icons.cancel,
                label: '错误',
                value: session.incorrectCount.toString(),
                color: Colors.red,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatCard(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
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
            size: 24,
            color: color,
          ),
          const SizedBox(height: 4),
          Text(
            value,
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
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPerformanceSection(BuildContext context, double accuracy) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.percent,
                color: _getAccuracyColor(accuracy),
              ),
              const SizedBox(width: 8),
              Text(
                '准确率',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${(accuracy * 100).toInt()}%',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: _getAccuracyColor(accuracy),
            ),
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: accuracy,
            backgroundColor: Theme.of(context).colorScheme.outline.withOpacity(0.3),
            valueColor: AlwaysStoppedAnimation<Color>(
              _getAccuracyColor(accuracy),
            ),
            minHeight: 6,
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Column(
      children: [
        if (session.incorrectCount > 0)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onRetryIncorrect,
              icon: const Icon(Icons.refresh),
              label: Text('重做错题 (${session.incorrectCount}题)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.secondary,
                foregroundColor: Theme.of(context).colorScheme.onSecondary,
              ),
            ),
          ),
        if (session.incorrectCount > 0) const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: onFinish,
            icon: const Icon(Icons.home),
            label: const Text('返回首页'),
          ),
        ),
      ],
    );
  }

  Color _getHeaderColor(BuildContext context, double accuracy) {
    if (accuracy >= 0.9) {
      return Colors.green;
    } else if (accuracy >= 0.7) {
      return Colors.orange;
    } else {
      return Colors.red;
    }
  }

  IconData _getHeaderIcon(double accuracy) {
    if (accuracy >= 0.9) {
      return Icons.emoji_events;
    } else if (accuracy >= 0.7) {
      return Icons.thumb_up;
    } else {
      return Icons.sentiment_neutral;
    }
  }

  String _getHeaderTitle(double accuracy) {
    if (accuracy >= 0.9) {
      return '太棒了！';
    } else if (accuracy >= 0.7) {
      return '不错！';
    } else {
      return '继续努力！';
    }
  }

  String _getHeaderSubtitle(double accuracy) {
    if (accuracy >= 0.9) {
      return '你的表现非常出色';
    } else if (accuracy >= 0.7) {
      return '你的表现还不错';
    } else {
      return '多练习会更好';
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
}