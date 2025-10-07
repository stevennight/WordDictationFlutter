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

class WordExplanationBatchService {
  final WordbookService _wordbookService = WordbookService();
  final WordService _wordService = WordService();
  final WordExplanationService _explanationService = WordExplanationService();

  Future<WordExplanationBatchSummary> generateForWordbook(
    int wordbookId, {
    bool overwriteExisting = false,
    String? sourceLanguage,
    String? targetLanguage,
  }) async {
    final words = await _wordbookService.getWordbookWords(wordbookId);
    return _generateForWords(
      words,
      overwriteExisting: overwriteExisting,
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
    );
  }

  Future<WordExplanationBatchSummary> generateForUnit(
    int unitId, {
    bool overwriteExisting = false,
    String? sourceLanguage,
    String? targetLanguage,
  }) async {
    final words = await _wordService.getWordsByUnitId(unitId);
    return _generateForWords(
      words,
      overwriteExisting: overwriteExisting,
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
    );
  }

  Future<WordExplanationBatchSummary> _generateForWords(
    List<Word> words, {
    required bool overwriteExisting,
    String? sourceLanguage,
    String? targetLanguage,
  }) async {
    final ai = await AIWordExplanationService.getInstance();
    int skipped = 0;
    int ok = 0;
    int fail = 0;

    for (final w in words) {
      try {
        // skip when explanation exists and not overwriting
        if (!overwriteExisting) {
          final existing = await _explanationService.getByWordId(w.id!);
          if (existing != null) {
            skipped++;
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
      } catch (_) {
        fail++;
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