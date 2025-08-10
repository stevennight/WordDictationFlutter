/// 默写结果数据模型
/// 
/// 此模型采用数据快照方式存储单词详细信息，包含以下快照字段：
/// - category: 单词分类快照
/// - partOfSpeech: 词性快照  
/// - level: 等级快照
/// 
/// 这些快照字段在创建默写结果时从 Word 模型复制而来，确保：
/// 1. 历史记录的独立性 - 即使原单词信息被修改，历史记录保持不变
/// 2. 数据完整性 - 避免因单词删除导致的外键约束问题
/// 3. 查询性能 - 减少多表关联查询的需要
/// 
/// 如果为 Word 模型添加新字段，请考虑是否需要在此处添加相应的快照字段。
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
  // Word detail fields for data snapshot approach - 单词详细信息快照字段
  final String? category;
  final String? partOfSpeech;
  final String? level;

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
    this.category,
    this.partOfSpeech,
    this.level,
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
    String? category,
    String? partOfSpeech,
    String? level,
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
      category: category ?? this.category,
      partOfSpeech: partOfSpeech ?? this.partOfSpeech,
      level: level ?? this.level,
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
      'category': category,
      'part_of_speech': partOfSpeech,
      'level': level,
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
      category: map['category'],
      partOfSpeech: map['part_of_speech'],
      level: map['level'],
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