import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../shared/models/dictation_session.dart';
import '../../../shared/models/dictation_result.dart';
import '../../../shared/providers/dictation_provider.dart';
import '../../../shared/providers/app_state_provider.dart';
import '../../../core/services/dictation_service.dart';
import '../../../core/services/local_config_service.dart';
import '../../../core/services/share_service.dart';
import 'package:file_picker/file_picker.dart';
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
          const SizedBox(height: 12),
          // 时间信息
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  icon: Icons.play_arrow,
                  label: '开始时间',
                  value: _formatTime(widget.session.startTime),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  icon: Icons.stop,
                  label: '结束时间',
                  value: widget.session.endTime != null 
                      ? _formatTime(widget.session.endTime!) 
                      : '未完成',
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
          // 第一行：查看详情和重做错题（如果有错题且不是来自历史页面）
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
                child: ElevatedButton.icon(
                  onPressed: _returnToHome,
                  icon: const Icon(Icons.home),
                  label: const Text('返回首页'),
                ),
              ),
            ],
          ),
          // 第二行：分享按钮
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _shareToApps,
                  icon: const Icon(Icons.share),
                  label: const Text('分享'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _saveToLocal,
                  icon: const Icon(Icons.save),
                  label: const Text('保存'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _copyToClipboard,
                  icon: const Icon(Icons.copy),
                  label: const Text('复制'),
                ),
              ),
            ],
          ),

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

  Future<void> _shareToApps() async {
    try {
      await ShareService.shareToApps(widget.session);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('分享失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _saveToLocal() async {
    try {
      // 让用户选择保存路径
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
      
      // 如果用户取消选择，直接返回
      if (selectedDirectory == null) {
        return;
      }
      
      // 让用户输入自定义文件名
      String? customFileName = await _showFileNameDialog();
      
      final filePath = await ShareService.saveToLocal(
        widget.session, 
        customPath: selectedDirectory,
        customFileName: customFileName,
      );
      
      if (filePath != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('图片已保存到: $filePath'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('保存失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  Future<String?> _showFileNameDialog() async {
    final TextEditingController controller = TextEditingController(
      text: 'dictation_result_${DateTime.now().millisecondsSinceEpoch}',
    );
    
    return showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('自定义文件名'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: '文件名（不需要输入.png后缀）',
              hintText: '例如：我的默写结果',
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                final fileName = controller.text.trim();
                Navigator.of(context).pop(fileName.isEmpty ? null : fileName);
              },
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _copyToClipboard() async {
    try {
      await ShareService.copyToClipboard(widget.session);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('图片已复制到剪贴板，可以直接粘贴到Word等应用中'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('复制失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _formatTime(DateTime dateTime) {
    return '${dateTime.year.toString().padLeft(4, '0')}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
}