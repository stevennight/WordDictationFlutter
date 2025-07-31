class Word {
  final int? id;
  final String prompt;  // 单词
  final String answer;  // 中文
  final String? category;  // 保留原有字段
  final String? partOfSpeech;  // 词性
  final String? level;  // 等级
  final int? wordbookId;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Word({
    this.id,
    required this.prompt,
    required this.answer,
    this.category,
    this.partOfSpeech,
    this.level,
    this.wordbookId,
    required this.createdAt,
    required this.updatedAt,
  });

  Word copyWith({
    int? id,
    String? prompt,
    String? answer,
    String? category,
    String? partOfSpeech,
    String? level,
    int? wordbookId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Word(
      id: id ?? this.id,
      prompt: prompt ?? this.prompt,
      answer: answer ?? this.answer,
      category: category ?? this.category,
      partOfSpeech: partOfSpeech ?? this.partOfSpeech,
      level: level ?? this.level,
      wordbookId: wordbookId ?? this.wordbookId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'prompt': prompt,
      'answer': answer,
      'category': category,
      'part_of_speech': partOfSpeech,
      'level': level,
      'wordbook_id': wordbookId,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
    };
  }

  factory Word.fromMap(Map<String, dynamic> map) {
    return Word(
      id: map['id']?.toInt(),
      prompt: map['prompt'] ?? '',
      answer: map['answer'] ?? '',
      category: map['category'],
      partOfSpeech: map['part_of_speech'],
      level: map['level'],
      wordbookId: map['wordbook_id']?.toInt(),
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at']),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at']),
    );
  }

  @override
  String toString() {
    return 'Word(id: $id, prompt: $prompt, answer: $answer, category: $category, partOfSpeech: $partOfSpeech, level: $level, createdAt: $createdAt, updatedAt: $updatedAt)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Word &&
        other.id == id &&
        other.prompt == prompt &&
        other.answer == answer &&
        other.category == category &&
        other.partOfSpeech == partOfSpeech &&
        other.level == level &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt;
  }

  @override
  int get hashCode {
    return id.hashCode ^
        prompt.hashCode ^
        answer.hashCode ^
        category.hashCode ^
        createdAt.hashCode ^
        updatedAt.hashCode;
  }
}