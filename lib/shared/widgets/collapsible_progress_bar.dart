import 'package:flutter/material.dart';

/// 可收起的进度信息栏组件
/// 默认收起状态，只显示基本进度信息，点击可展开显示详细统计
class CollapsibleProgressBar extends StatefulWidget {
  final int current;
  final int total;
  final int correct;
  final int incorrect;
  final bool showStats;
  final String? title;
  final VoidCallback? onExit;

  const CollapsibleProgressBar({
    super.key,
    required this.current,
    required this.total,
    required this.correct,
    required this.incorrect,
    this.showStats = true,
    this.title,
    this.onExit,
  });

  // Alternative constructor for copying mode
  const CollapsibleProgressBar.copying({
    super.key,
    required int currentIndex,
    required int totalCount,
    required double accuracy,
    required int correctCount,
    bool? showStats,
    String? title,
    VoidCallback? onExit,
  }) : current = currentIndex,
       total = totalCount,
       correct = correctCount,
       incorrect = 0,
       showStats = showStats ?? false,
       title = title,
       onExit = onExit;

  @override
  State<CollapsibleProgressBar> createState() => _CollapsibleProgressBarState();
}

class _CollapsibleProgressBarState extends State<CollapsibleProgressBar>
    with SingleTickerProviderStateMixin {
  bool _isExpanded = false; // 默认收起
  
  late AnimationController _animationController;
  late Animation<double> _heightAnimation;

  @override
  void initState() {
    super.initState();
    
    // 初始化动画控制器
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    
    _heightAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _toggleExpanded() {
    setState(() {
      _isExpanded = !_isExpanded;
    });
    
    if (_isExpanded) {
      _animationController.forward();
    } else {
      _animationController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = widget.total > 0 ? widget.current / widget.total : 0.0;
    final accuracy = (widget.correct + widget.incorrect) > 0 
        ? widget.correct / (widget.correct + widget.incorrect) 
        : 0.0;

    return Container(
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
            // 基本进度信息（始终显示）
            GestureDetector(
              onTap: widget.showStats ? _toggleExpanded : null,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    // 进度图标和标题
                    Icon(
                      Icons.timeline,
                      size: 20,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      widget.title ?? '进度',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    
                    const SizedBox(width: 16),
                    
                    // 进度条和数字
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(
                            child: LinearProgressIndicator(
                              value: progress,
                              backgroundColor: Theme.of(context).colorScheme.outline.withOpacity(0.3),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Theme.of(context).colorScheme.primary,
                              ),
                              minHeight: 4,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '${widget.current}/${widget.total}',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    // 快速统计信息（收起状态下显示）
                    if (!_isExpanded && widget.showStats) ..._buildQuickStats(accuracy),
                    
                    // 退出按钮
                    if (widget.onExit != null) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: widget.onExit,
                        icon: const Icon(
                          Icons.close,
                          color: Colors.red,
                          size: 20,
                        ),
                        tooltip: '退出默写',
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(24, 24),
                        ),
                      ),
                    ],
                    
                    // 展开/收起按钮
                    if (widget.showStats) ...[
                      const SizedBox(width: 8),
                      AnimatedRotation(
                        turns: _isExpanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 300),
                        child: Icon(
                          Icons.expand_less,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            
            // 详细统计信息（可展开）
            if (widget.showStats)
              AnimatedBuilder(
                animation: _heightAnimation,
                builder: (context, child) {
                  return ClipRect(
                    child: Align(
                      alignment: Alignment.topCenter,
                      heightFactor: _heightAnimation.value,
                      child: child,
                    ),
                  );
                },
                child: _buildDetailedStats(accuracy),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildQuickStats(double accuracy) {
    return [
      // 准确率快速显示
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: _getAccuracyColor(accuracy).withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _getAccuracyColor(accuracy).withOpacity(0.3),
          ),
        ),
        child: Text(
          '${(accuracy * 100).round()}%',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: _getAccuracyColor(accuracy),
          ),
        ),
      ),
    ];
  }

  Widget _buildDetailedStats(double accuracy) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        children: [
          // 分隔线
          Container(
            height: 1,
            color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
            margin: const EdgeInsets.only(bottom: 16),
          ),
          
          // 详细统计卡片
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  context,
                  icon: Icons.check_circle,
                  label: '正确',
                  value: widget.correct.toString(),
                  color: Colors.green,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildStatCard(
                  context,
                  icon: Icons.cancel,
                  label: '错误',
                  value: widget.incorrect.toString(),
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
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
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
            size: 20,
            color: color,
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
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