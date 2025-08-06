class Unit {
  final int? id;
  final String name;
  final String? description;
  final int wordbookId;
  final int wordCount;
  final bool isLearned; // 是否已学习
  final DateTime createdAt;
  final DateTime updatedAt;

  const Unit({
    this.id,
    required this.name,
    this.description,
    required this.wordbookId,
    required this.wordCount,
    this.isLearned = false,
    required this.createdAt,
    required this.updatedAt,
  });

  Unit copyWith({
    int? id,
    String? name,
    String? description,
    int? wordbookId,
    int? wordCount,
    bool? isLearned,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Unit(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      wordbookId: wordbookId ?? this.wordbookId,
      wordCount: wordCount ?? this.wordCount,
      isLearned: isLearned ?? this.isLearned,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'wordbook_id': wordbookId,
      'word_count': wordCount,
      'is_learned': isLearned ? 1 : 0,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
    };
  }

  factory Unit.fromMap(Map<String, dynamic> map) {
    return Unit(
      id: map['id']?.toInt(),
      name: map['name'] ?? '',
      description: map['description'],
      wordbookId: map['wordbook_id']?.toInt() ?? 0,
      wordCount: map['word_count']?.toInt() ?? 0,
      isLearned: (map['is_learned'] ?? 0) == 1,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at']),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at']),
    );
  }

  @override
  String toString() {
    return 'Unit(id: $id, name: $name, description: $description, wordbookId: $wordbookId, wordCount: $wordCount, isLearned: $isLearned, createdAt: $createdAt, updatedAt: $updatedAt)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Unit &&
        other.id == id &&
        other.name == name &&
        other.description == description &&
        other.wordbookId == wordbookId &&
        other.wordCount == wordCount &&
        other.isLearned == isLearned &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt;
  }

  @override
  int get hashCode {
    return id.hashCode ^
        name.hashCode ^
        description.hashCode ^
        wordbookId.hashCode ^
        wordCount.hashCode ^
        isLearned.hashCode ^
        createdAt.hashCode ^
        updatedAt.hashCode;
  }
}