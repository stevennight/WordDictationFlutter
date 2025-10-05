import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_word_dictation/shared/models/dictation_result.dart';
import 'package:flutter_word_dictation/shared/models/word.dart';

void main() {
  group('DictationResult Data Snapshot Tests', () {
    test('should create DictationResult with word details snapshot', () {
      // Arrange
      final word = Word(
        id: 1,
        prompt: 'hello',
        answer: '你好',
        category: '日常用语',
        partOfSpeech: 'n.',
        level: 'CET4',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // Act
      final result = DictationResult(
        sessionId: 'test-session-123',
        wordId: word.id!,
        prompt: word.prompt,
        answer: word.answer,
        isCorrect: true,
        wordIndex: 0,
        timestamp: DateTime.now(),
        // Store word details as snapshot
        category: word.category,
        partOfSpeech: word.partOfSpeech,
        level: word.level,
      );

      // Assert
      expect(result.wordId, equals(1));
      expect(result.category, equals('日常用语'));
      expect(result.partOfSpeech, equals('n.'));
      expect(result.level, equals('CET4'));
    });

    test('should serialize and deserialize DictationResult with word details', () {
      // Arrange
      final originalResult = DictationResult(
        sessionId: 'test-session-456',
        wordId: 2,
        prompt: 'world',
        answer: '世界',
        isCorrect: false,
        wordIndex: 1,
        timestamp: DateTime.now(),
        category: '抽象概念',
        partOfSpeech: 'n.',
        level: 'CET6',
      );

      // Act
      final map = originalResult.toMap();
      final deserializedResult = DictationResult.fromMap(map);

      // Assert
      expect(deserializedResult.sessionId, equals(originalResult.sessionId));
      expect(deserializedResult.wordId, equals(originalResult.wordId));
      expect(deserializedResult.category, equals(originalResult.category));
      expect(deserializedResult.partOfSpeech, equals(originalResult.partOfSpeech));
      expect(deserializedResult.level, equals(originalResult.level));
    });

    test('should handle null word details gracefully', () {
      // Arrange & Act
      final result = DictationResult(
        sessionId: 'test-session-789',
        wordId: 3,
        prompt: 'test',
        answer: '测试',
        isCorrect: true,
        wordIndex: 2,
        timestamp: DateTime.now(),
        // All word details are null
        category: null,
        partOfSpeech: null,
        level: null,
      );

      // Assert
      expect(result.category, isNull);
      expect(result.partOfSpeech, isNull);
      expect(result.level, isNull);

      // Should still serialize/deserialize correctly
      final map = result.toMap();
      final deserializedResult = DictationResult.fromMap(map);
      expect(deserializedResult.category, isNull);
      expect(deserializedResult.partOfSpeech, isNull);
      expect(deserializedResult.level, isNull);
    });
  });
}