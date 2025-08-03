enum DictationMode {
  sequential,
  random,
  retry,
}

enum SessionStatus {
  inProgress,
  completed,
  paused,
}

class DictationSession {
  final int? id;
  final String sessionId;
  final String? wordFileName;
  final DictationMode mode;
  final SessionStatus status;
  final int totalWords;
  final int currentWordIndex;
  final int correctCount;
  final int incorrectCount;
  final DateTime startTime;
  final DateTime? endTime;
  final bool isRetrySession;
  final String? originalSessionId;
  final int dictationDirection; // 0: 原文→译文, 1: 译文→原文

  const DictationSession({
    this.id,
    required this.sessionId,
    this.wordFileName,
    required this.mode,
    required this.status,
    required this.totalWords,
    this.currentWordIndex = 0,
    this.correctCount = 0,
    this.incorrectCount = 0,
    required this.startTime,
    this.endTime,
    this.isRetrySession = false,
    this.originalSessionId,
    this.dictationDirection = 0, // 默认原文→译文
  });

  DictationSession copyWith({
    int? id,
    String? sessionId,
    String? wordFileName,
    DictationMode? mode,
    SessionStatus? status,
    int? totalWords,
    int? currentWordIndex,
    int? correctCount,
    int? incorrectCount,
    DateTime? startTime,
    DateTime? endTime,
    bool? isRetrySession,
    String? originalSessionId,
    int? dictationDirection,
  }) {
    return DictationSession(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      wordFileName: wordFileName ?? this.wordFileName,
      mode: mode ?? this.mode,
      status: status ?? this.status,
      totalWords: totalWords ?? this.totalWords,
      currentWordIndex: currentWordIndex ?? this.currentWordIndex,
      correctCount: correctCount ?? this.correctCount,
      incorrectCount: incorrectCount ?? this.incorrectCount,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      isRetrySession: isRetrySession ?? this.isRetrySession,
      originalSessionId: originalSessionId ?? this.originalSessionId,
      dictationDirection: dictationDirection ?? this.dictationDirection,
    );
  }

  double get accuracy {
    final total = correctCount + incorrectCount;
    return total > 0 ? (correctCount / total) * 100 : 0.0;
  }

  Duration? get duration {
    if (endTime != null) {
      return endTime!.difference(startTime);
    }
    return null;
  }

  bool get isCompleted => status == SessionStatus.completed;

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'session_id': sessionId,
      'word_file_name': wordFileName,
      'mode': mode.index,
      'status': status.index,
      'total_words': totalWords,
      'current_word_index': currentWordIndex,
      'correct_count': correctCount,
      'incorrect_count': incorrectCount,
      'start_time': startTime.millisecondsSinceEpoch,
      'end_time': endTime?.millisecondsSinceEpoch,
      'is_retry_session': isRetrySession ? 1 : 0,
      'original_session_id': originalSessionId,
      'dictation_direction': dictationDirection,
    };
    
    // Only include id if it's not null (for updates)
    if (id != null) {
      map['id'] = id;
    }
    
    return map;
  }

  factory DictationSession.fromMap(Map<String, dynamic> map) {
    return DictationSession(
      id: map['id']?.toInt(),
      sessionId: map['session_id'] ?? '',
      wordFileName: map['word_file_name'],
      mode: DictationMode.values[map['mode'] ?? 0],
      status: SessionStatus.values[map['status'] ?? 0],
      totalWords: map['total_words']?.toInt() ?? 0,
      currentWordIndex: map['current_word_index']?.toInt() ?? 0,
      correctCount: map['correct_count']?.toInt() ?? 0,
      incorrectCount: map['incorrect_count']?.toInt() ?? 0,
      startTime: DateTime.fromMillisecondsSinceEpoch(map['start_time']),
      endTime: map['end_time'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['end_time'])
          : null,
      isRetrySession: (map['is_retry_session'] ?? 0) == 1,
      originalSessionId: map['original_session_id'],
      dictationDirection: map['dictation_direction']?.toInt() ?? 0,
    );
  }

  @override
  String toString() {
    return 'DictationSession(id: $id, sessionId: $sessionId, wordFileName: $wordFileName, mode: $mode, status: $status, totalWords: $totalWords, currentWordIndex: $currentWordIndex, correctCount: $correctCount, incorrectCount: $incorrectCount, startTime: $startTime, endTime: $endTime, isRetrySession: $isRetrySession, originalSessionId: $originalSessionId)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DictationSession && other.sessionId == sessionId;
  }

  @override
  int get hashCode => sessionId.hashCode;
}