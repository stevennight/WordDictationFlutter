import 'package:flutter/material.dart';

class FileDropZone extends StatefulWidget {
  final Function(String) onFileSelected;
  final bool isLoading;
  final String? fileName;
  final int wordCount;

  const FileDropZone({
    super.key,
    required this.onFileSelected,
    required this.isLoading,
    this.fileName,
    required this.wordCount,
  });

  @override
  State<FileDropZone> createState() => _FileDropZoneState();
}

class _FileDropZoneState extends State<FileDropZone>
    with SingleTickerProviderStateMixin {
  bool _isDragOver = false;
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 1.05,
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

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _scaleAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Container(
            height: 120,
            decoration: BoxDecoration(
              border: Border.all(
                color: _isDragOver
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.outline,
                width: _isDragOver ? 2 : 1,
                style: BorderStyle.solid,
              ),
              borderRadius: BorderRadius.circular(12),
              color: _isDragOver
                  ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.1)
                  : Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
            ),
            child: widget.isLoading
                ? _buildLoadingState()
                : widget.fileName != null
                    ? _buildFileLoadedState()
                    : _buildEmptyState(),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.cloud_upload_outlined,
          size: 48,
          color: _isDragOver
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: 8),
        Text(
          _isDragOver ? '松开以导入文件' : '拖拽文件到此处',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: _isDragOver
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: _isDragOver ? FontWeight.w500 : null,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '支持 .xlsx、.docx、.csv 格式',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildLoadingState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(
            strokeWidth: 3,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '正在导入文件...',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildFileLoadedState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            Icons.description,
            size: 32,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          widget.fileName!,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w500,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '${widget.wordCount} 个单词',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSecondaryContainer,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  void _handleDragEnter() {
    setState(() {
      _isDragOver = true;
    });
    _animationController.forward();
  }

  void _handleDragLeave() {
    setState(() {
      _isDragOver = false;
    });
    _animationController.reverse();
  }

  void _handleDragDrop(String filePath) {
    setState(() {
      _isDragOver = false;
    });
    _animationController.reverse();
    
    final extension = filePath.split('.').last.toLowerCase();
    if (extension == 'xlsx' || extension == 'docx' || extension == 'csv') {
      widget.onFileSelected(filePath);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请选择 .xlsx、.docx 或 .csv 格式的文件'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}