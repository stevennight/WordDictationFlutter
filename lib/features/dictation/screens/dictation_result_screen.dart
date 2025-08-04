import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../shared/models/dictation_session.dart';
import '../../../shared/models/dictation_result.dart';
import '../../../shared/providers/dictation_provider.dart';
import '../../../shared/providers/app_state_provider.dart';
import '../../../core/services/dictation_service.dart';
import '../../../core/services/local_config_service.dart';
import '../../../shared/utils/accuracy_header_utils.dart';
import '../../history/screens/history_detail_screen.dart';
import '../../../main.dart';

class DictationResultScreen extends StatefulWidget {
  final DictationSession session;
  final List<DictationResult> results;

  const DictationResultScreen({
    super.key,
    required this.session,
    required this.results,
  });

  @override
  State<DictationResultScreen> createState() => _DictationResultScreenState();
}

class _DictationResultScreenState extends State<DictationResultScreen> {
  final DictationService _dictationService = DictationService();

  @override
  Widget build(BuildContext context) {
    final accuracy = widget.session.accuracy;
    final duration = widget.session.duration;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('默写结果'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.home),
            onPressed: _returnToHome,
            tooltip: '返回首页',
          ),
        ],
      ),
      body: Column(
              children: [
                // 统计信息头部 - 可滚动
                Expanded(
                  child: SingleChildScrollView(
                    child: _buildStatisticsHeader(accuracy, duration),
                  ),
                ),
                
                // 底部操作按钮
                _buildActionButtons(),
              ],
            ),
    );
  }

  Widget _buildStatisticsHeader(double accuracy, Duration? duration) {
    final durationText = duration != null
        ? '${duration.inMinutes}分${duration.inSeconds % 60}秒'
        : '未知';
    
    return FutureBuilder<Color>(
      future: AccuracyHeaderUtils.getHeaderColor(accuracy),
      builder: (context, colorSnapshot) {
        final headerColor = colorSnapshot.data ?? Colors.grey;
        
        return FutureBuilder<IconData>(
          future: AccuracyHeaderUtils.getHeaderIcon(accuracy),
          builder: (context, iconSnapshot) {
            final headerIcon = iconSnapshot.data ?? Icons.help;
            
            return Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: headerColor,
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(20),
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    headerIcon,
                    size: 48,
                    color: Colors.white,
                  ),
          const SizedBox(height: 12),
          FutureBuilder<String>(
            future: AccuracyHeaderUtils.getHeaderTitle(accuracy),
            builder: (context, snapshot) {
              return Text(
                snapshot.data ?? '加载中...',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
              );
            },
          ),
          const SizedBox(height: 8),
          if (widget.session.wordFileName != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.description,
                    size: 16,
                    color: Colors.white70,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      widget.session.wordFileName!,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.white70,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
          FutureBuilder<String>(
            future: AccuracyHeaderUtils.getHeaderSubtitle(accuracy),
            builder: (context, snapshot) {
              return Text(
                snapshot.data ?? '加载中...',
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.white70,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
                textAlign: TextAlign.center,
              );
            },
          ),
          const SizedBox(height: 16),
          
          // 统计卡片
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  icon: Icons.quiz,
                  label: '总题数',
                  value: widget.session.totalWords.toString(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  icon: Icons.timer,
                  label: '用时',
                  value: durationText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  icon: Icons.check_circle,
                  label: '正确',
                  value: widget.session.correctCount.toString(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  icon: Icons.cancel,
                  label: '错误',
                  value: widget.session.incorrectCount.toString(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // 准确率
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.percent,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '准确率',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '${accuracy.toInt()}%',
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: accuracy / 100,
                  backgroundColor: Colors.white.withOpacity(0.3),
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                  minHeight: 6,
                ),
              ],
            ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Icon(
            icon,
            size: 20,
            color: Colors.white,
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }







  Widget _buildActionButtons() {
    final hasIncorrectWords = widget.results.any((r) => !r.isCorrect);
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 第一行：查看详情和重做错题（如果有错题）
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _viewDetails,
                  icon: const Icon(Icons.visibility),
                  label: const Text('查看详情'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: hasIncorrectWords
                    ? OutlinedButton.icon(
                        onPressed: _retryIncorrectWords,
                        icon: const Icon(Icons.refresh),
                        label: const Text('重做错题'),
                      )
                    : ElevatedButton.icon(
                        onPressed: _returnToHome,
                        icon: const Icon(Icons.home),
                        label: const Text('返回首页'),
                      ),
              ),
            ],
          ),
          // 第二行：如果有错题，显示返回首页按钮
          if (hasIncorrectWords) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _returnToHome,
                icon: const Icon(Icons.home),
                label: const Text('返回首页'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // 使用共享工具类AccuracyHeaderUtils替代重复方法

  void _viewDetails() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => HistoryDetailScreen(
          sessionId: widget.session.sessionId,
        ),
      ),
    );
  }

  void _retryIncorrectWords() {
    final dictationProvider = context.read<DictationProvider>();
    dictationProvider.retryIncorrectWords();
    Navigator.of(context).pop();
  }

  void _returnToHome() {
    final dictationProvider = context.read<DictationProvider>();
    final appState = context.read<AppStateProvider>();
    
    dictationProvider.finishSession();
    appState.exitDictationMode();
    
    // Use pushAndRemoveUntil to ensure we return to the main screen
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const MainScreen()),
      (route) => false,
    );
  }
}