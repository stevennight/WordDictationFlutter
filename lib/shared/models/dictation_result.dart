class DictationResult {
  final int? id;
  final String sessionId;
  final int wordId;
  final String prompt;
  final String answer;
  final bool isCorrect;
  final String? originalImagePath;
  final String? annotatedImagePath;
  final int wordIndex;
  final DateTime timestamp;
  final String? userNotes;

  const DictationResult({
    this.id,
    required this.sessionId,
    required this.wordId,
    required this.prompt,
    required this.answer,
    required this.isCorrect,
    this.originalImagePath,
    this.annotatedImagePath,
    required this.wordIndex,
    required this.timestamp,
    this.userNotes,
  });

  DictationResult copyWith({
    int? id,
    String? sessionId,
    int? wordId,
    String? prompt,
    String? answer,
    bool? isCorrect,
    String? originalImagePath,
    String? annotatedImagePath,
    int? wordIndex,
    DateTime? timestamp,
    String? userNotes,
  }) {
    return DictationResult(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      wordId: wordId ?? this.wordId,
      prompt: prompt ?? this.prompt,
      answer: answer ?? this.answer,
      isCorrect: isCorrect ?? this.isCorrect,
      originalImagePath: originalImagePath ?? this.originalImagePath,
      annotatedImagePath: annotatedImagePath ?? this.annotatedImagePath,
      wordIndex: wordIndex ?? this.wordIndex,
      timestamp: timestamp ?? this.timestamp,
      userNotes: userNotes ?? this.userNotes,
    );
  }

  bool get hasOriginalImage => originalImagePath != null && originalImagePath!.isNotEmpty;
  bool get hasAnnotatedImage => annotatedImagePath != null && annotatedImagePath!.isNotEmpty;
  bool get hasImages => hasOriginalImage || hasAnnotatedImage;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'session_id': sessionId,
      'word_id': wordId,
      'prompt': prompt,
      'answer': answer,
      'is_correct': isCorrect ? 1 : 0,
      'original_image_path': originalImagePath,
      'annotated_image_path': annotatedImagePath,
      'word_index': wordIndex,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'user_notes': userNotes,
    };
  }

  factory DictationResult.fromMap(Map<String, dynamic> map) {
    return DictationResult(
      id: map['id']?.toInt(),
      sessionId: map['session_id'] ?? '',
      wordId: map['word_id']?.toInt() ?? 0,
      prompt: map['prompt'] ?? '',
      answer: map['answer'] ?? '',
      isCorrect: (map['is_correct'] ?? 0) == 1,
      originalImagePath: map['original_image_path'],
      annotatedImagePath: map['annotated_image_path'],
      wordIndex: map['word_index']?.toInt() ?? 0,
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp']),
      userNotes: map['user_notes'],
    );
  }

  @override
  String toString() {
    return 'DictationResult(id: $id, sessionId: $sessionId, wordId: $wordId, prompt: $prompt, answer: $answer, isCorrect: $isCorrect, originalImagePath: $originalImagePath, annotatedImagePath: $annotatedImagePath, wordIndex: $wordIndex, timestamp: $timestamp, userNotes: $userNotes)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DictationResult &&
        other.id == id &&
        other.sessionId == sessionId &&
        other.wordId == wordId &&
        other.wordIndex == wordIndex;
  }

  @override
  int get hashCode {
    return id.hashCode ^
        sessionId.hashCode ^
        wordId.hashCode ^
        wordIndex.hashCode;
  }
}