/// 单词数据模型
/// 
/// 注意：当单词被用于默写时，其详细信息（category、partOfSpeech、level等）
/// 会被复制到 dictation_results 表中作为数据快照，以确保历史记录的独立性。
/// 这意味着即使后续修改了单词表中的这些字段，历史默写记录仍会保持当时的数据状态。
/// 
/// 如果需要为单词表添加新字段，请考虑是否也需要在 DictationResult 模型中
/// 添加相应的快照字段，以保持数据一致性。
class Word {
  final int? id;
  final String prompt;  // 单词
  final String answer;  // 中文
  final String? category;  // 保留原有字段
  final String? partOfSpeech;  // 词性
  final String? level;  // 等级
  final int? wordbookId;
  final int? unitId;  // 单元ID
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
    this.unitId,
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
    int? unitId,
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
      unitId: unitId ?? this.unitId,
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
      'unit_id': unitId,
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
      unitId: map['unit_id']?.toInt(),
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