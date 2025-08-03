import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'dart:io';

import '../../../shared/models/dictation_result.dart';
import '../../../shared/models/word.dart';
import '../../../shared/providers/dictation_provider.dart';
import '../../../core/services/word_service.dart';
import '../../dictation/screens/copying_screen.dart';

class ResultDetailCard extends StatefulWidget {
  final DictationResult result;
  final int index;

  const ResultDetailCard({
    super.key,
    required this.result,
    required this.index,
  });

  @override
  State<ResultDetailCard> createState() => _ResultDetailCardState();
}

class _ResultDetailCardState extends State<ResultDetailCard> {
  Word? _word;
  bool _isLoadingWord = false;

  @override
  void initState() {
    super.initState();
    _loadWordDetails();
  }

  Future<void> _loadWordDetails() async {
    if (widget.result.wordId <= 0) return;
    
    setState(() {
      _isLoadingWord = true;
    });
    
    try {
      final wordService = WordService();
      final word = await wordService.getWordById(widget.result.wordId);
      if (mounted) {
        setState(() {
          _word = word;
          _isLoadingWord = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingWord = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: widget.result.isCorrect
                        ? Colors.green.withOpacity(0.1)
                        : Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: widget.result.isCorrect ? Colors.green : Colors.red,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      widget.index.toString(),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: widget.result.isCorrect ? Colors.green : Colors.red,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '提示: ${widget.result.prompt}',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        DateFormat('HH:mm:ss').format(widget.result.timestamp),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                // Status indicator and copy button
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: widget.result.isCorrect
                          ? Colors.green.withOpacity(0.1)
                          : Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: widget.result.isCorrect ? Colors.green : Colors.red,
                      ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            widget.result.isCorrect ? Icons.check : Icons.close,
                            size: 14,
                            color: widget.result.isCorrect ? Colors.green : Colors.red,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            widget.result.isCorrect ? '正确' : '错误',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: widget.result.isCorrect ? Colors.green : Colors.red,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Copy button
                    InkWell(
                      onTap: () => _startCopying(context),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.blue.withOpacity(0.3),
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.edit,
                              size: 14,
                              color: Colors.blue,
                            ),
                            SizedBox(width: 4),
                            Text(
                              '抄写',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: Colors.blue,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            
            const SizedBox(height: 12),
            
            // Answer section
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '正确答案',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.result.answer,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  
                  // 词性和等级信息
                  if (_word != null && (_word!.partOfSpeech != null || _word!.level != null)) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        if (_word!.partOfSpeech != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.secondaryContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              _word!.partOfSpeech!,
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.onSecondaryContainer,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        if (_word!.partOfSpeech != null && _word!.level != null)
                          const SizedBox(width: 8),
                        if (_word!.level != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.tertiaryContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              _word!.level!,
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.onTertiaryContainer,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            
            const SizedBox(height: 12),
            
            // Handwriting images
            if (widget.result.originalImagePath != null || widget.result.annotatedImagePath != null)
              _buildHandwritingSection(context),
            
            // Notes section
            if (widget.result.userNotes != null && widget.result.userNotes!.isNotEmpty)
              _buildNotesSection(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHandwritingSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '手写内容',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        
        Row(
          children: [
            if (widget.result.originalImagePath != null)
              Expanded(
                child: _buildImageCard(
                  context,
                  '原始手写',
                  widget.result.originalImagePath!,
                ),
              ),
            if (widget.result.originalImagePath != null && widget.result.annotatedImagePath != null)
              const SizedBox(width: 8),
            if (widget.result.annotatedImagePath != null)
              Expanded(
                child: _buildImageCard(
                  context,
                  '批注版本',
                  widget.result.annotatedImagePath!,
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildImageCard(BuildContext context, String title, String imagePath) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: () => _showImageDialog(context, imagePath, title),
          child: Container(
            height: 120,
            width: double.infinity,
            decoration: BoxDecoration(
              border: Border.all(
                color: Theme.of(context).colorScheme.outline.withOpacity(0.5),
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: _buildImage(imagePath),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildImage(String imagePath) {
    final file = File(imagePath);
    
    if (!file.existsSync()) {
      return Container(
        color: Colors.grey[200],
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.image_not_supported,
                size: 32,
                color: Colors.grey,
              ),
              SizedBox(height: 4),
              Text(
                '图片不存在',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Image.file(
      file,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) {
        return Container(
          color: Colors.grey[200],
          child: const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.broken_image,
                  size: 32,
                  color: Colors.grey,
                ),
                SizedBox(height: 4),
                Text(
                  '加载失败',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildNotesSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '备注',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
            ),
          ),
          child: Text(
            widget.result.userNotes!,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }

  void _showImageDialog(BuildContext context, String imagePath, String title) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBar(
              title: Text(title),
              automaticallyImplyLeading: false,
              actions: [
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            Flexible(
              child: Container(
                constraints: const BoxConstraints(
                  maxHeight: 500,
                  maxWidth: 400,
                ),
                child: _buildImage(imagePath),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _startCopying(BuildContext context) async {
    try {
      final dictationProvider = Provider.of<DictationProvider>(context, listen: false);
      
      // Use the loaded word if available, otherwise create a basic word object
      final word = _word ?? Word(
        prompt: widget.result.prompt,
        answer: widget.result.answer,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      
      // Load single word for copying
      await dictationProvider.loadWordsFromWordbook(
        words: [word],
        wordbookName: '历史记录',
        mode: 1, // copying mode
        order: 0, // order doesn't matter for single word
        count: 1,
      );

      if (context.mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => const CopyingScreen(),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('启动抄写失败: $e')),
        );
      }
    }
  }
}