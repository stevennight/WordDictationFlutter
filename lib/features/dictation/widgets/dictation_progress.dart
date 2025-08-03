import 'package:flutter/material.dart';

class DictationProgress extends StatelessWidget {
  final int current;
  final int total;
  final int correct;
  final int incorrect;
  final bool showStats;

  const DictationProgress({
    super.key,
    required this.current,
    required this.total,
    required this.correct,
    required this.incorrect,
    this.showStats = true,
  });

  // Alternative constructor for copying mode
  const DictationProgress.copying({
    super.key,
    required int currentIndex,
    required int totalCount,
    required double accuracy,
    required int correctCount,
    bool? showStats,
  }) : current = currentIndex,
       total = totalCount,
       correct = correctCount,
       incorrect = 0,
       showStats = showStats ?? false;

  @override
  Widget build(BuildContext context) {
    final progress = total > 0 ? current / total : 0.0;
    final accuracy = (correct + incorrect) > 0 
        ? correct / (correct + incorrect) 
        : 0.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Progress bar
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '进度',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            '$current / $total',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: progress,
                        backgroundColor: Theme.of(context).colorScheme.outline.withOpacity(0.3),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Theme.of(context).colorScheme.primary,
                        ),
                        minHeight: 6,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            
            if (showStats) ...[
              const SizedBox(height: 16),
              
              // Statistics
              Row(
                children: [
                  Expanded(
                    child: _buildStatCard(
                      context,
                      icon: Icons.check_circle,
                      label: '正确',
                      value: correct.toString(),
                      color: Colors.green,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildStatCard(
                      context,
                      icon: Icons.cancel,
                      label: '错误',
                      value: incorrect.toString(),
                      color: Colors.red,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildStatCard(
                      context,
                      icon: Icons.percent,
                      label: '准确率',
                      value: '${(accuracy * 100).round()}%',
                      color: _getAccuracyColor(accuracy),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
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
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: color.withOpacity(0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            '$label: $value',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
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