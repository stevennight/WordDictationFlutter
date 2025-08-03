import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../shared/models/dictation_session.dart';
import '../../../shared/models/dictation_result.dart';
import '../../../shared/models/word.dart';
import '../../../shared/providers/dictation_provider.dart';
import '../../../shared/providers/app_state_provider.dart';
import '../../../core/services/dictation_service.dart';
import '../../../core/services/word_service.dart';
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
  final WordService _wordService = WordService();
  List<Word> _words = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadWords();
  }

  Future<void> _loadWords() async {
    try {
      final wordIds = widget.results.map((r) => r.wordId).toList();
      final words = <Word>[];
      
      for (final wordId in wordIds) {
        final word = await _wordService.getWordById(wordId);
        if (word != null) {
          words.add(word);
        }
      }
      
      setState(() {
        _words = words;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载单词失败: $e')),
        );
      }
    }
  }

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
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // 统计信息头部
                _buildStatisticsHeader(accuracy, duration),
                
                // 详细结果列表
                Expanded(
                  child: _buildResultsList(),
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
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _getHeaderColor(accuracy),
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(20),
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
          const SizedBox(height: 8),
          Text(
            _getHeaderSubtitle(accuracy),
            style: const TextStyle(
              fontSize: 16,
              color: Colors.white70,
            ),
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

  Widget _buildResultsList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: widget.results.length,
      itemBuilder: (context, index) {
        final result = widget.results[index];
        final word = _words.isNotEmpty && index < _words.length 
            ? _words[index] 
            : null;
        
        return _buildResultItem(result, word, index + 1);
      },
    );
  }

  Widget _buildResultItem(DictationResult result, Word? word, int index) {
    final session = widget.session;
    final dictationDirection = session.dictationDirection;
    
    // 根据默写方向确定显示内容
    final promptText = dictationDirection == 0 ? result.prompt : result.answer;
    final answerText = dictationDirection == 0 ? result.answer : result.prompt;
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 题目信息
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: result.isCorrect ? Colors.green : Colors.red,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      index.toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            result.isCorrect ? Icons.check_circle : Icons.cancel,
                            color: result.isCorrect ? Colors.green : Colors.red,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            result.isCorrect ? '正确' : '错误',
                            style: TextStyle(
                              color: result.isCorrect ? Colors.green : Colors.red,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      if (word?.partOfSpeech != null || word?.level != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Wrap(
                            spacing: 8,
                            children: [
                              if (word?.partOfSpeech != null)
                                Chip(
                                  label: Text(
                                    word!.partOfSpeech!,
                                    style: const TextStyle(fontSize: 10),
                                  ),
                                  backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
                                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                              if (word?.level != null)
                                Chip(
                                  label: Text(
                                    word!.level!,
                                    style: const TextStyle(fontSize: 10),
                                  ),
                                  backgroundColor: Theme.of(context).colorScheme.tertiaryContainer,
                                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 12),
            
            // 题目内容
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceVariant,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '题目：',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    promptText,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 8),
            
            // 正确答案
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.green.withOpacity(0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '正确答案：',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.green.shade700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    answerText,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.green.shade700,
                    ),
                  ),
                ],
              ),
            ),
            
            // 手写图片
            if (result.originalImagePath != null || result.annotatedImagePath != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: _buildHandwritingImages(result),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHandwritingImages(DictationResult result) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '手写笔迹：',
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            if (result.originalImagePath != null)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '原始笔迹',
                      style: TextStyle(
                        fontSize: 10,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      height: 120,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.asset(
                          result.originalImagePath!,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) {
                            return const Center(
                              child: Icon(
                                Icons.image_not_supported,
                                color: Colors.grey,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (result.originalImagePath != null && result.annotatedImagePath != null)
              const SizedBox(width: 12),
            if (result.annotatedImagePath != null)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '批改笔迹',
                      style: TextStyle(
                        fontSize: 10,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      height: 120,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.asset(
                          result.annotatedImagePath!,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) {
                            return const Center(
                              child: Icon(
                                Icons.image_not_supported,
                                color: Colors.grey,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
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
          // 第一行：查看详情按钮
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _viewDetails,
              icon: const Icon(Icons.visibility),
              label: const Text('查看详情'),
            ),
          ),
          const SizedBox(height: 12),
          // 第二行：重做错题和返回首页
          Row(
            children: [
              if (hasIncorrectWords)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _retryIncorrectWords,
                    icon: const Icon(Icons.refresh),
                    label: const Text('重做错题'),
                  ),
                ),
              if (hasIncorrectWords) const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _returnToHome,
                  icon: const Icon(Icons.home),
                  label: const Text('返回首页'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _getHeaderColor(double accuracy) {
    if (accuracy >= 90) {
      return Colors.green;
    } else if (accuracy >= 70) {
      return Colors.orange;
    } else {
      return Colors.red;
    }
  }

  IconData _getHeaderIcon(double accuracy) {
    if (accuracy >= 90) {
      return Icons.emoji_events;
    } else if (accuracy >= 70) {
      return Icons.thumb_up;
    } else {
      return Icons.sentiment_dissatisfied;
    }
  }

  String _getHeaderTitle(double accuracy) {
    if (accuracy >= 90) {
      return '优秀！';
    } else if (accuracy >= 70) {
      return '良好！';
    } else {
      return '继续努力！';
    }
  }

  String _getHeaderSubtitle(double accuracy) {
    if (accuracy >= 90) {
      return '表现出色，继续保持！';
    } else if (accuracy >= 70) {
      return '不错的成绩，再接再厉！';
    } else {
      return '多加练习，你会更好的！';
    }
  }

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