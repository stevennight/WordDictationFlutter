class Wordbook {
  final int? id;
  final String name;
  final String? description;
  final String? originalFileName;
  final int wordCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Wordbook({
    this.id,
    required this.name,
    this.description,
    this.originalFileName,
    required this.wordCount,
    required this.createdAt,
    required this.updatedAt,
  });

  Wordbook copyWith({
    int? id,
    String? name,
    String? description,
    String? originalFileName,
    int? wordCount,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Wordbook(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      originalFileName: originalFileName ?? this.originalFileName,
      wordCount: wordCount ?? this.wordCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'original_file_name': originalFileName,
      'word_count': wordCount,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
    };
  }

  factory Wordbook.fromMap(Map<String, dynamic> map) {
    return Wordbook(
      id: map['id']?.toInt(),
      name: map['name'] ?? '',
      description: map['description'],
      originalFileName: map['original_file_name'],
      wordCount: map['word_count']?.toInt() ?? 0,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at']),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at']),
    );
  }

  @override
  String toString() {
    return 'Wordbook(id: $id, name: $name, wordCount: $wordCount)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Wordbook && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}