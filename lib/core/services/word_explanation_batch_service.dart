import 'dart:async';

import 'package:flutter_word_dictation/core/services/ai_word_explanation_service.dart';
import 'package:flutter_word_dictation/core/services/word_explanation_service.dart';
import 'package:flutter_word_dictation/core/services/word_service.dart';
import 'package:flutter_word_dictation/core/services/wordbook_service.dart';
import 'package:flutter_word_dictation/shared/models/word.dart';
import 'package:flutter_word_dictation/shared/models/word_explanation.dart';

class WordExplanationBatchSummary {
  final int total;
  final int skippedExisting;
  final int succeeded;
  final int failed;

  const WordExplanationBatchSummary({
    required this.total,
    required this.skippedExisting,
    required this.succeeded,
    required this.failed,
  });
}

class WordExplanationProgress {
  final int current; // 已处理数量（含跳过/成功/失败）
  final int total; // 总数
  final Word word; // 当前处理的单词
  final int skippedExisting; // 累计跳过数
  final int succeeded; // 累计成功数
  final int failed; // 累计失败数
  final String status; // 'skipped' | 'succeeded' | 'failed'

  const WordExplanationProgress({
    required this.current,
    required this.total,
    required this.word,
    required this.skippedExisting,
    required this.succeeded,
    required this.failed,
    required this.status,
  });
}

class WordExplanationBatchService {
  final WordbookService _wordbookService = WordbookService();
  final WordService _wordService = WordService();
  final WordExplanationService _explanationService = WordExplanationService();

  Future<WordExplanationBatchSummary> generateForWordbook(
    int wordbookId, {
    bool overwriteExisting = false,
    String? sourceLanguage,
    String? targetLanguage,
    void Function(WordExplanationProgress)? onProgress,
  }) async {
    final words = await _wordbookService.getWordbookWords(wordbookId);
    return _generateForWords(
      words,
      overwriteExisting: overwriteExisting,
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
      onProgress: onProgress,
    );
  }

  Future<WordExplanationBatchSummary> generateForUnit(
    int unitId, {
    bool overwriteExisting = false,
    String? sourceLanguage,
    String? targetLanguage,
    void Function(WordExplanationProgress)? onProgress,
  }) async {
    final words = await _wordService.getWordsByUnitId(unitId);
    return _generateForWords(
      words,
      overwriteExisting: overwriteExisting,
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
      onProgress: onProgress,
    );
  }

  Future<WordExplanationBatchSummary> _generateForWords(
    List<Word> words, {
    required bool overwriteExisting,
    String? sourceLanguage,
    String? targetLanguage,
    void Function(WordExplanationProgress)? onProgress,
  }) async {
    final ai = await AIWordExplanationService.getInstance();
    int skipped = 0;
    int ok = 0;
    int fail = 0;
    final total = words.length;

    for (final w in words) {
      try {
        // skip when explanation exists and not overwriting
        if (!overwriteExisting) {
          final existing = await _explanationService.getByWordId(w.id!);
          if (existing != null) {
            skipped++;
            onProgress?.call(WordExplanationProgress(
              current: skipped + ok + fail,
              total: total,
              word: w,
              skippedExisting: skipped,
              succeeded: ok,
              failed: fail,
              status: 'skipped',
            ));
            continue;
          }
        }

        final html = await ai.generateExplanationHtml(
          prompt: w.prompt,
          answer: w.answer,
          sourceLanguage: sourceLanguage,
          targetLanguage: targetLanguage,
        );

        final now = DateTime.now();
        final explanation = WordExplanation(
          wordId: w.id!,
          html: html,
          sourceModel: null,
          createdAt: now,
          updatedAt: now,
        );
        await _explanationService.upsertForWord(explanation);
        ok++;
        onProgress?.call(WordExplanationProgress(
          current: skipped + ok + fail,
          total: total,
          word: w,
          skippedExisting: skipped,
          succeeded: ok,
          failed: fail,
          status: 'succeeded',
        ));
      } catch (_) {
        fail++;
        onProgress?.call(WordExplanationProgress(
          current: skipped + ok + fail,
          total: total,
          word: w,
          skippedExisting: skipped,
          succeeded: ok,
          failed: fail,
          status: 'failed',
        ));
      }
    }

    return WordExplanationBatchSummary(
      total: words.length,
      skippedExisting: skipped,
      succeeded: ok,
      failed: fail,
    );
  }
}