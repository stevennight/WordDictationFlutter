import 'package:flutter/material.dart';

class HistoryStatsCard extends StatelessWidget {
  final int totalSessions;
  final int completedSessions;
  final double averageAccuracy;
  final Duration totalTime;

  const HistoryStatsCard({
    super.key,
    required this.totalSessions,
    required this.completedSessions,
    required this.averageAccuracy,
    required this.totalTime,
  });

  @override
  Widget build(BuildContext context) {
    final completionRate = totalSessions > 0 ? completedSessions / totalSessions : 0.0;
    
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.analytics,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  '统计概览',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Stats grid
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    context,
                    icon: Icons.quiz,
                    label: '总会话',
                    value: totalSessions.toString(),
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    context,
                    icon: Icons.check_circle,
                    label: '已完成',
                    value: completedSessions.toString(),
                    color: Colors.green,
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 12),
            
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    context,
                    icon: Icons.percent,
                    label: '完成率',
                    value: '${(completionRate * 100).toInt()}%',
                    color: _getCompletionRateColor(completionRate),
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    context,
                    icon: Icons.trending_up,
                    label: '平均准确率',
                    value: '${(averageAccuracy * 100).toInt()}%',
                    color: _getAccuracyColor(averageAccuracy),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 12),
            
            // Total time
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.access_time,
                    size: 20,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '总用时: ${_formatDuration(totalTime)}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(
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
            color: color,
            size: 24,
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
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

  Color _getCompletionRateColor(double rate) {
    if (rate >= 0.8) {
      return Colors.green;
    } else if (rate >= 0.5) {
      return Colors.orange;
    } else {
      return Colors.red;
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

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    
    if (hours > 0) {
      return '${hours}小时${minutes}分钟';
    } else {
      return '${minutes}分钟';
    }
  }
}