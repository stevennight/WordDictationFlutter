class WordExplanation {
  final int? id;
  final int wordId;
  final String html;
  final String? sourceModel;
  final DateTime createdAt;
  final DateTime updatedAt;

  const WordExplanation({
    this.id,
    required this.wordId,
    required this.html,
    this.sourceModel,
    required this.createdAt,
    required this.updatedAt,
  });

  WordExplanation copyWith({
    int? id,
    int? wordId,
    String? html,
    String? sourceModel,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return WordExplanation(
      id: id ?? this.id,
      wordId: wordId ?? this.wordId,
      html: html ?? this.html,
      sourceModel: sourceModel ?? this.sourceModel,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory WordExplanation.fromMap(Map<String, dynamic> map) {
    return WordExplanation(
      id: map['id'] as int?,
      wordId: map['word_id'] as int,
      html: (map['html'] ?? '') as String,
      sourceModel: map['source_model'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'word_id': wordId,
      'html': html,
      'source_model': sourceModel,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
    };
  }
}