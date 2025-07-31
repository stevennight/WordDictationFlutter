import 'package:flutter/material.dart';

enum HistoryFilter {
  all,
  completed,
  incomplete,
}

enum HistorySortBy {
  dateDesc,
  dateAsc,
  accuracyDesc,
  accuracyAsc,
  durationDesc,
  durationAsc,
}

class HistoryFilterDialog extends StatefulWidget {
  final HistoryFilter currentFilter;
  final HistorySortBy currentSortBy;

  const HistoryFilterDialog({
    super.key,
    required this.currentFilter,
    required this.currentSortBy,
  });

  @override
  State<HistoryFilterDialog> createState() => _HistoryFilterDialogState();
}

class _HistoryFilterDialogState extends State<HistoryFilterDialog> {
  late HistoryFilter _selectedFilter;
  late HistorySortBy _selectedSortBy;

  @override
  void initState() {
    super.initState();
    _selectedFilter = widget.currentFilter;
    _selectedSortBy = widget.currentSortBy;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('筛选和排序'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Filter section
            Text(
              '筛选条件',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            
            _buildFilterOption(
              HistoryFilter.all,
              '全部',
              Icons.list,
            ),
            _buildFilterOption(
              HistoryFilter.completed,
              '已完成',
              Icons.check_circle,
            ),
            _buildFilterOption(
              HistoryFilter.incomplete,
              '未完成',
              Icons.pending,
            ),
            
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),
            
            // Sort section
            Text(
              '排序方式',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            
            _buildSortOption(
              HistorySortBy.dateDesc,
              '时间（最新优先）',
              Icons.schedule,
            ),
            _buildSortOption(
              HistorySortBy.dateAsc,
              '时间（最旧优先）',
              Icons.history,
            ),
            _buildSortOption(
              HistorySortBy.accuracyDesc,
              '准确率（高到低）',
              Icons.trending_up,
            ),
            _buildSortOption(
              HistorySortBy.accuracyAsc,
              '准确率（低到高）',
              Icons.trending_down,
            ),
            _buildSortOption(
              HistorySortBy.durationDesc,
              '用时（长到短）',
              Icons.timer,
            ),
            _buildSortOption(
              HistorySortBy.durationAsc,
              '用时（短到长）',
              Icons.timer_off,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () {
            // Reset to defaults
            setState(() {
              _selectedFilter = HistoryFilter.all;
              _selectedSortBy = HistorySortBy.dateDesc;
            });
          },
          child: const Text('重置'),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.of(context).pop({
              'filter': _selectedFilter,
              'sortBy': _selectedSortBy,
            });
          },
          child: const Text('应用'),
        ),
      ],
    );
  }

  Widget _buildFilterOption(
    HistoryFilter filter,
    String title,
    IconData icon,
  ) {
    final isSelected = _selectedFilter == filter;
    
    return InkWell(
      onTap: () {
        setState(() {
          _selectedFilter = filter;
        });
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.primaryContainer
              : null,
          borderRadius: BorderRadius.circular(8),
          border: isSelected
              ? Border.all(
                  color: Theme.of(context).colorScheme.primary,
                )
              : null,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
              ),
            ),
            if (isSelected)
              Icon(
                Icons.check,
                size: 20,
                color: Theme.of(context).colorScheme.primary,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSortOption(
    HistorySortBy sortBy,
    String title,
    IconData icon,
  ) {
    final isSelected = _selectedSortBy == sortBy;
    
    return InkWell(
      onTap: () {
        setState(() {
          _selectedSortBy = sortBy;
        });
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.primaryContainer
              : null,
          borderRadius: BorderRadius.circular(8),
          border: isSelected
              ? Border.all(
                  color: Theme.of(context).colorScheme.primary,
                )
              : null,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
              ),
            ),
            if (isSelected)
              Icon(
                Icons.check,
                size: 20,
                color: Theme.of(context).colorScheme.primary,
              ),
          ],
        ),
      ),
    );
  }
}

class HistoryFilterOptions {
  final HistoryFilter filter;
  final HistorySortBy sortBy;

  const HistoryFilterOptions({
    required this.filter,
    required this.sortBy,
  });

  HistoryFilterOptions copyWith({
    HistoryFilter? filter,
    HistorySortBy? sortBy,
  }) {
    return HistoryFilterOptions(
      filter: filter ?? this.filter,
      sortBy: sortBy ?? this.sortBy,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is HistoryFilterOptions &&
        other.filter == filter &&
        other.sortBy == sortBy;
  }

  @override
  int get hashCode => filter.hashCode ^ sortBy.hashCode;
}