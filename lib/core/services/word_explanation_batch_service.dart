import 'dart:async';

import 'package:flutter_word_dictation/core/services/ai_word_explanation_service.dart';
import 'package:flutter_word_dictation/core/services/word_explanation_service.dart';
import 'package:flutter_word_dictation/core/services/word_service.dart';
import 'package:flutter_word_dictation/core/services/wordbook_service.dart';
import 'package:flutter_word_dictation/core/services/config_service.dart';
import 'package:flutter_word_dictation/shared/models/word.dart';
import 'package:flutter_word_dictation/shared/models/word_explanation.dart';

class WordExplanationBatchSummary {
  final int total;
  final int skippedExisting;
  final int succeeded;
  final int failed;
  final List<Word> failedWords;

  const WordExplanationBatchSummary({
    required this.total,
    required this.skippedExisting,
    required this.succeeded,
    required this.failed,
    this.failedWords = const [],
  });
}

enum WordExplanationDetailedStatus {
  queued('队列中'),
  normalizing('单词归一化'),
  dictionaryQuery('词典查询'),
  generatingDefinition('生成基础释义中'),
  generatingExamples('生成例句中'),
  generatingExtended('生成扩展内容中'),
  reflectingDefinition('释义内容反思中'),
  reflectingExamples('例句内容反思中'),
  reflectingExtended('扩展内容反思中'),
  completed('生成完成'),
  failed('生成失败');

  const WordExplanationDetailedStatus(this.displayName);
  final String displayName;
}

class WordExplanationProgress {
  final int current; // 已处理数量（含跳过/成功/失败）
  final int total; // 总数
  final Word word; // 当前处理的单词
  final int skippedExisting; // 累计跳过数
  final int succeeded; // 累计成功数
  final int failed; // 累计失败数
  final String status; // 'skipped' | 'succeeded' | 'failed'
  final WordExplanationDetailedStatus? detailedStatus; // 详细状态
  final String? errorMessage; // 错误信息（仅当status为failed时有值）

  const WordExplanationProgress({
    required this.current,
    required this.total,
    required this.word,
    required this.skippedExisting,
    required this.succeeded,
    required this.failed,
    required this.status,
    this.detailedStatus,
    this.errorMessage,
  });

  WordExplanationProgress copyWith({
    int? current,
    int? total,
    Word? word,
    int? skippedExisting,
    int? succeeded,
    int? failed,
    String? status,
    WordExplanationDetailedStatus? detailedStatus,
    String? errorMessage,
  }) {
    return WordExplanationProgress(
      current: current ?? this.current,
      total: total ?? this.total,
      word: word ?? this.word,
      skippedExisting: skippedExisting ?? this.skippedExisting,
      succeeded: succeeded ?? this.succeeded,
      failed: failed ?? this.failed,
      status: status ?? this.status,
      detailedStatus: detailedStatus ?? this.detailedStatus,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
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
    void Function(WordExplanationDetailedStatus)? onDetailedProgress,
    bool Function()? isCancelled,
  }) async {
    final words = await _wordbookService.getWordbookWords(wordbookId);
    return _generateForWords(
      words,
      overwriteExisting: overwriteExisting,
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
      onProgress: onProgress,
      onDetailedProgress: onDetailedProgress,
      isCancelled: isCancelled,
    );
  }

  Future<WordExplanationBatchSummary> generateForUnit(
    int unitId, {
    bool overwriteExisting = false,
    String? sourceLanguage,
    String? targetLanguage,
    void Function(WordExplanationProgress)? onProgress,
    void Function(WordExplanationDetailedStatus)? onDetailedProgress,
    bool Function()? isCancelled,
  }) async {
    final words = await _wordService.getWordsByUnitId(unitId);
    return _generateForWords(
      words,
      overwriteExisting: overwriteExisting,
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
      onProgress: onProgress,
      onDetailedProgress: onDetailedProgress,
      isCancelled: isCancelled,
    );
  }

  /// Retry failed words from a previous batch operation
  Future<WordExplanationBatchSummary> retryFailedWords(
    List<Word> failedWords, {
    String? sourceLanguage,
    String? targetLanguage,
    void Function(WordExplanationProgress)? onProgress,
    void Function(WordExplanationDetailedStatus)? onDetailedProgress,
    bool Function()? isCancelled,
  }) async {
    return _generateForWords(
      failedWords,
      overwriteExisting: true, // Always overwrite for retries
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
      onProgress: onProgress,
      onDetailedProgress: onDetailedProgress,
      isCancelled: isCancelled,
    );
  }

  Future<WordExplanationBatchSummary> _generateForWords(
    List<Word> words, {
    required bool overwriteExisting,
    String? sourceLanguage,
    String? targetLanguage,
    void Function(WordExplanationProgress)? onProgress,
    void Function(WordExplanationDetailedStatus)? onDetailedProgress,
    bool Function()? isCancelled,
  }) async {
    final ai = await AIWordExplanationService.getInstance();
    int skipped = 0;
    int ok = 0;
    int fail = 0;
    final total = words.length;
    final List<Word> failedWords = [];

    // 获取并发数配置
    final cfg = await ConfigService.getInstance();
    final concurrency = await cfg.getAIConcurrency();

    // 初始化所有单词为"待处理"状态
    for (int i = 0; i < words.length; i++) {
      final w = words[i];
      onProgress?.call(WordExplanationProgress(
        current: 0,
        total: total,
        word: w,
        skippedExisting: 0,
        succeeded: 0,
        failed: 0,
        status: 'pending',
        detailedStatus: WordExplanationDetailedStatus.queued,
      ));
      // 每初始化10个单词就yield一次，让UI有机会更新
      if (i % 10 == 9) {
        await Future.delayed(Duration.zero);
      }
    }
    
    // 初始化完成后稍作等待，确保UI完全更新
    await Future.delayed(const Duration(milliseconds: 50));

    // 动态并发处理：一个完成就补充一个新的
    int currentIndex = 0;
    final activeCompleters = <Completer<void>>[];
    bool isCancelRequested = false; // 中断请求标志

    // 处理单个单词的函数
    Future<void> processWord(Word w) async {
      // 检查是否已中断
      if (isCancelled != null && isCancelled()) {
        skipped++;
        onProgress?.call(WordExplanationProgress(
          current: skipped + ok + fail,
          total: total,
          word: w,
          skippedExisting: skipped,
          succeeded: ok,
          failed: fail,
          status: 'skipped',
          detailedStatus: WordExplanationDetailedStatus.completed,
        ));
        return;
      }

      try {
        // Report queued status (不增加 current，因为还未完成)
        onProgress?.call(WordExplanationProgress(
          current: skipped + ok + fail, // 只计算已完成的
          total: total,
          word: w,
          skippedExisting: skipped,
          succeeded: ok,
          failed: fail,
          status: 'processing',
          detailedStatus: WordExplanationDetailedStatus.queued,
        ));

        // skip when explanation exists and not overwriting
        if (!overwriteExisting) {
          final existing = await _explanationService.getByWordId(w.id!);
          if (existing != null) {
            skipped++;
            onProgress?.call(WordExplanationProgress(
              current: skipped + ok + fail, // 跳过也算完成
              total: total,
              word: w,
              skippedExisting: skipped,
              succeeded: ok,
              failed: fail,
              status: 'skipped',
              detailedStatus: WordExplanationDetailedStatus.completed,
            ));
            return;
          }
        }

        try {
          final html = await ai.generateExplanationJson(
            prompt: w.prompt,
            answer: w.answer,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            onDetailedProgress: (status) {
              onDetailedProgress?.call(status);
              onProgress?.call(WordExplanationProgress(
                current: skipped + ok + fail, // 处理中不增加 current
                total: total,
                word: w,
                skippedExisting: skipped,
                succeeded: ok,
                failed: fail,
                status: 'processing',
                detailedStatus: status,
              ));
            },
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
            current: skipped + ok + fail, // 成功完成，增加 current
            total: total,
            word: w,
            skippedExisting: skipped,
            succeeded: ok,
            failed: fail,
            status: 'succeeded',
            detailedStatus: WordExplanationDetailedStatus.completed,
          ));
        } catch (e) {
          rethrow;
        }
      } catch (e) {
        fail++;
        failedWords.add(w);
        onProgress?.call(WordExplanationProgress(
          current: skipped + ok + fail, // 失败也算完成，增加 current
          total: total,
          word: w,
          skippedExisting: skipped,
          succeeded: ok,
          failed: fail,
          status: 'failed',
          detailedStatus: WordExplanationDetailedStatus.failed,
          errorMessage: e.toString(),
        ));
      }
    }
    
    // 包装处理函数
    Future<void> processWithCompleter(Word w, Completer<void> completer) async {
      try {
        await processWord(w);
      } finally {
        completer.complete();
      }
    }

    // 启动初始并发任务
    while (currentIndex < words.length && activeCompleters.length < concurrency) {
      final completer = Completer<void>();
      activeCompleters.add(completer);
      processWithCompleter(words[currentIndex], completer);
      currentIndex++;
    }

    // 动态补充：一个完成就启动下一个
    while (activeCompleters.isNotEmpty) {
      // 等待任意一个完成
      await Future.any(activeCompleters.map((c) => c.future));

      // 移除已完成的
      activeCompleters.removeWhere((c) => c.isCompleted);

      // 检查是否已中断
      if (isCancelled != null && isCancelled()) {
        if (!isCancelRequested) {
          isCancelRequested = true; // 设置中断请求标志
        }
        // 等待所有活动任务完成
        if (activeCompleters.isNotEmpty) {
          await Future.wait(activeCompleters.map((c) => c.future));
        }
        break;
      }

      // 补充新任务
      while (currentIndex < words.length && activeCompleters.length < concurrency) {
        final completer = Completer<void>();
        activeCompleters.add(completer);
        processWithCompleter(words[currentIndex], completer);
        currentIndex++;
      }
    }

    return WordExplanationBatchSummary(
      total: words.length,
      skippedExisting: skipped,
      succeeded: ok,
      failed: fail,
      failedWords: failedWords,
    );
  }
}
