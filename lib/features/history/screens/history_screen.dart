import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../shared/models/dictation_session.dart';
import '../../../shared/models/word.dart';
import '../../../shared/providers/app_state_provider.dart';
import '../../../shared/providers/dictation_provider.dart';
import '../../../shared/providers/history_provider.dart';
import '../../dictation/screens/dictation_result_screen.dart';
import '../widgets/history_card.dart';
import '../widgets/history_filter_dialog.dart';
import '../widgets/history_stats_card.dart';
import 'history_detail_screen.dart';


class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  HistoryFilter _selectedFilter = HistoryFilter.all;
  HistorySortBy _selectedSort = HistorySortBy.dateDesc;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<HistoryProvider>().loadHistory();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Consumer<HistoryProvider>(
        builder: (context, historyProvider, child) {
          if (historyProvider.isLoading) {
            return CustomScrollView(
              slivers: [
                SliverAppBar(
                  title: const Text('历史记录'),
                  floating: true,
                  snap: true,
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  foregroundColor: Theme.of(context).colorScheme.onSurface,
                  surfaceTintColor: Theme.of(context).colorScheme.primary,
                ),
                const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                ),
              ],
            );
          }

          final sessions = _getFilteredSessions(historyProvider.sessions);

          return RefreshIndicator(
            onRefresh: () => historyProvider.loadHistory(),
            child: CustomScrollView(
              controller: _scrollController,
              slivers: [
                SliverAppBar(
                  title: const Text('历史记录'),
                  floating: true,
                  snap: true,
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  foregroundColor: Theme.of(context).colorScheme.onSurface,
                  surfaceTintColor: Theme.of(context).colorScheme.primary,
                ),
                
                // Statistics section
                if (historyProvider.sessions.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: HistoryStatsCard(
                        totalSessions: historyProvider.sessions.length,
                        completedSessions: historyProvider.sessions.where((s) => s.isCompleted).length,
                        averageAccuracy: historyProvider.sessions.where((s) => s.isCompleted).isEmpty ? 0.0 : historyProvider.sessions.where((s) => s.isCompleted).map((s) => s.accuracy).reduce((a, b) => a + b) / historyProvider.sessions.where((s) => s.isCompleted).length,
                        totalTime: historyProvider.sessions.fold(Duration.zero, (total, session) => total + (session.duration ?? Duration.zero)),
                      ),
                    ),
                  ),

                // Filter and sort controls
                SliverToBoxAdapter(
                  child: _buildControlsSection(historyProvider),
                ),

                // History list
                if (sessions.isEmpty)
                  SliverFillRemaining(
                    child: _buildEmptyState(),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final session = sessions[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: HistoryCard(
                              session: session,
                              onTap: () => _navigateToDetail(session),
                              onDelete: () => _deleteSession(historyProvider, session),
                              onRetry: session.incorrectCount > 0
                                  ? () => _retrySession(historyProvider, session)
                                  : null,
                              onShare: () => _shareSession(historyProvider, session),
                            ),
                          );
                        },
                        childCount: sessions.length,
                      ),
                    ),
                  ),

                // Bottom padding
                const SliverToBoxAdapter(
                  child: SizedBox(height: 16),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildControlsSection(HistoryProvider historyProvider) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // Filter button
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _showFilterDialog(),
              icon: const Icon(Icons.filter_list),
              label: Text(_getFilterLabel()),
            ),
          ),
          const SizedBox(width: 12),
          
          // Sort button
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _showSortDialog(),
              icon: const Icon(Icons.sort),
              label: Text(_getSortLabel()),
            ),
          ),
          const SizedBox(width: 12),
          
          // Clear all button
          IconButton(
            onPressed: historyProvider.sessions.isEmpty
                ? null
                : () => _showClearAllDialog(historyProvider),
            icon: const Icon(Icons.delete_sweep),
            tooltip: '清空历史',
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.history,
            size: 64,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            _selectedFilter == HistoryFilter.all ? '暂无历史记录' : '没有符合条件的记录',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _selectedFilter == HistoryFilter.all 
                ? '完成默写后会在这里显示历史记录'
                : '尝试调整筛选条件',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  List<DictationSession> _getFilteredSessions(List<DictationSession> sessions) {
    var filtered = sessions.where((session) {
      switch (_selectedFilter) {
        case HistoryFilter.completed:
          return session.isCompleted;
        case HistoryFilter.incomplete:
          return !session.isCompleted;
        case HistoryFilter.all:
          return true;
      }
    }).toList();

    // Sort sessions
    filtered.sort((a, b) {
      switch (_selectedSort) {
        case HistorySortBy.dateAsc:
          return a.startTime.compareTo(b.startTime);
        case HistorySortBy.accuracyDesc:
          return b.accuracy.compareTo(a.accuracy);
        case HistorySortBy.accuracyAsc:
          return a.accuracy.compareTo(b.accuracy);
        case HistorySortBy.dateDesc:
        default:
          return b.startTime.compareTo(a.startTime);
      }
    });

    return filtered;
  }

  String _getFilterLabel() {
    switch (_selectedFilter) {
      case HistoryFilter.completed:
        return '已完成';
      case HistoryFilter.incomplete:
        return '未完成';
      case HistoryFilter.all:
        return '全部';
    }
  }

  String _getSortLabel() {
    switch (_selectedSort) {
      case HistorySortBy.dateAsc:
        return '时间↑';
      case HistorySortBy.accuracyDesc:
        return '准确率↓';
      case HistorySortBy.accuracyAsc:
        return '准确率↑';
      case HistorySortBy.dateDesc:
      default:
        return '时间↓';
    }
  }

  void _showFilterDialog() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => HistoryFilterDialog(
        currentFilter: _selectedFilter,
        currentSortBy: _selectedSort,
      ),
    );
    
    if (result != null) {
      setState(() {
        _selectedFilter = result['filter'];
        _selectedSort = result['sortBy'];
      });
    }
  }

  void _showSortDialog() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '排序方式',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            ..._buildSortOptions(),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildSortOptions() {
    final options = [
      (HistorySortBy.dateDesc, '时间（新到旧）', Icons.schedule),
      (HistorySortBy.dateAsc, '时间（旧到新）', Icons.schedule),
      (HistorySortBy.accuracyDesc, '准确率（高到低）', Icons.trending_down),
      (HistorySortBy.accuracyAsc, '准确率（低到高）', Icons.trending_up),
    ];

    return options.map((option) {
      final isSelected = _selectedSort == option.$1;
      return ListTile(
        leading: Icon(option.$3),
        title: Text(option.$2),
        trailing: isSelected ? const Icon(Icons.check) : null,
        selected: isSelected,
        onTap: () {
          setState(() {
            _selectedSort = option.$1;
          });
          Navigator.of(context).pop();
        },
      );
    }).toList();
  }

  void _showClearAllDialog(HistoryProvider historyProvider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空历史记录'),
        content: const Text('确定要清空所有历史记录吗？此操作无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              historyProvider.clearAllHistory();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _navigateToDetail(DictationSession session) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => HistoryDetailScreen(sessionId: session.sessionId),
      ),
    );
  }

  void _deleteSession(HistoryProvider historyProvider, DictationSession session) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除记录'),
        content: const Text('确定要删除这条记录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              historyProvider.deleteSession(session.sessionId);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  Future<void> _retrySession(HistoryProvider historyProvider, DictationSession session) async {
    try {
      final incorrectResults = await historyProvider.getIncorrectResultsForSession(session.sessionId);
      
      if (incorrectResults.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('该会话没有错题可以重做')),
          );
        }
        return;
      }
      
      // 显示重做模式选择对话框
      final selectedMode = await showDialog<DictationMode>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('选择重做模式'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('共有 ${incorrectResults.length} 个错题需要重做'),
              const SizedBox(height: 16),
              const Text('请选择重做顺序：'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(DictationMode.sequential),
              child: const Text('顺序重做'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(DictationMode.random),
              child: const Text('乱序重做'),
            ),
          ],
        ),
      );
      
      if (selectedMode == null) return;
      
      // 将错题结果转换为Word对象
      final retryWords = incorrectResults.map((result) => Word(
        id: result.wordId,
        prompt: result.prompt,
        answer: result.answer,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      )).toList();
      
      // 使用DictationProvider加载错题并开始重做模式
      final dictationProvider = context.read<DictationProvider>();
      final appState = context.read<AppStateProvider>();
      
      await dictationProvider.loadWords(retryWords);
      
      // 开始重做默写，使用用户选择的模式
      await dictationProvider.startDictation(
        mode: selectedMode,
        wordFileName: '${session.wordFileName ?? '未知文件'} - 错题重做',
        dictationDirection: session.dictationDirection,
      );
      
      // 进入默写模式
      appState.enterDictationMode(
        wordFileName: '${session.wordFileName ?? '未知文件'} - 错题重做',
        totalWords: retryWords.length,
      );
      
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('开始重做错题失败: $e')),
        );
      }
    }
  }

  void _shareSession(HistoryProvider historyProvider, DictationSession session) async {
    try {
      // 获取session的详细结果
      final results = await historyProvider.getSessionResults(session.sessionId);
      
      // 导航到默写结果页面
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => DictationResultScreen(
              session: session,
              results: results,
            ),
          ),
        );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载分享数据失败: $e')),
        );
      }
    }
  }
}