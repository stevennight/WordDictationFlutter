class ExampleSentence {
  final int? id;
  final int wordId;
  final int senseIndex; // 对应译文序号
  final String textPlain; // 纯文本
  final String textHtml; // 包含 ruby 的HTML
  final String textTranslation; // 句子整体译文
  final String grammarNote; // 语法说明，格式：【<语法>】：语法解释。
  final String? sourceModel; // 生成来源模型
  final DateTime createdAt;
  final DateTime updatedAt;

  const ExampleSentence({
    this.id,
    required this.wordId,
    required this.senseIndex,
    required this.textPlain,
    required this.textHtml,
    required this.textTranslation,
    required this.grammarNote,
    this.sourceModel,
    required this.createdAt,
    required this.updatedAt,
  });

  ExampleSentence copyWith({
    int? id,
    int? wordId,
    int? senseIndex,
    String? textPlain,
    String? textHtml,
    String? textTranslation,
    String? grammarNote,
    String? sourceModel,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ExampleSentence(
      id: id ?? this.id,
      wordId: wordId ?? this.wordId,
      senseIndex: senseIndex ?? this.senseIndex,
      textPlain: textPlain ?? this.textPlain,
      textHtml: textHtml ?? this.textHtml,
      textTranslation: textTranslation ?? this.textTranslation,
      grammarNote: grammarNote ?? this.grammarNote,
      sourceModel: sourceModel ?? this.sourceModel,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'word_id': wordId,
      'sense_index': senseIndex,
      'text_plain': textPlain,
      'text_html': textHtml,
      'text_translation': textTranslation,
       'grammar_note': grammarNote,
      'source_model': sourceModel,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
    };
  }

  factory ExampleSentence.fromMap(Map<String, dynamic> map) {
    return ExampleSentence(
      id: map['id']?.toInt(),
      wordId: map['word_id']?.toInt() ?? 0,
      senseIndex: map['sense_index']?.toInt() ?? 0,
      textPlain: map['text_plain'] ?? '',
      textHtml: map['text_html'] ?? '',
      textTranslation: map['text_translation'] ?? '',
      grammarNote: map['grammar_note'] ?? '',
      sourceModel: map['source_model'],
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] ?? DateTime.now().millisecondsSinceEpoch),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] ?? DateTime.now().millisecondsSinceEpoch),
    );
  }
}