import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/word.dart';
import '../models/dictation_session.dart';
import '../models/dictation_result.dart';
import '../../core/services/dictation_service.dart';
import '../../core/services/word_service.dart';

enum DictationState {
  idle,
  loading,
  ready,
  inProgress,
  showingAnswer,
  judging,
  completed,
  error,
}

class DictationProvider extends ChangeNotifier {
  final DictationService _dictationService = DictationService();
  final WordService _wordService = WordService();
  final Uuid _uuid = const Uuid();
  
  // State
  DictationState _state = DictationState.idle;
  DictationSession? _currentSession;
  List<Word> _words = [];
  List<Word> _sessionWords = [];
  List<DictationResult> _results = [];
  Word? _currentWord;
  String? _errorMessage;
  
  // Canvas state
  String? _originalImagePath;
  String? _annotatedImagePath;
  bool _isAnnotationMode = false;
  
  // Getters
  DictationState get state => _state;
  DictationSession? get currentSession => _currentSession;
  List<Word> get words => _words;
  List<Word> get sessionWords => _sessionWords;
  List<DictationResult> get results => _results;
  Word? get currentWord => _currentWord;
  String? get errorMessage => _errorMessage;
  String? get originalImagePath => _originalImagePath;
  String? get annotatedImagePath => _annotatedImagePath;
  bool get isAnnotationMode => _isAnnotationMode;
  
  // Computed properties
  bool get hasWords => _words.isNotEmpty;
  bool get hasCurrentWord => _currentWord != null;
  bool get canStartDictation => hasWords && _state == DictationState.ready;
  bool get isInProgress => _state == DictationState.inProgress;
  bool get isShowingAnswer => _state == DictationState.showingAnswer;
  bool get isJudging => _state == DictationState.judging;
  bool get isCompleted => _state == DictationState.completed;
  bool get hasError => _state == DictationState.error;
  
  int get currentWordIndex {
    return _currentSession?.currentWordIndex ?? 0;
  }
  
  int get currentIndex {
    return currentWordIndex;
  }
  
  int get totalWords {
    return _sessionWords.length;
  }
  
  int get correctCount {
    return _results.where((r) => r.isCorrect).length;
  }
  
  int get incorrectCount {
    return _results.where((r) => !r.isCorrect).length;
  }
  
  double get accuracy {
    if (_results.isEmpty) return 0.0;
    return (correctCount / _results.length) * 100;
  }
  
  List<DictationResult> get incorrectResults {
    return _results.where((r) => !r.isCorrect).toList();
  }
  
  // Actions
  Future<void> loadWords(List<Word> words) async {
    try {
      _setState(DictationState.loading);
      _words = words;
      _setState(DictationState.ready);
    } catch (e) {
      _setError('加载单词失败: $e');
    }
  }

  Future<void> loadWordsFromWordbook({
    required List<Word> words,
    required String wordbookName,
    required int mode,
    required int order,
    required int count,
  }) async {
    try {
      _setState(DictationState.loading);
      
      // Load words
      _words = words;
      
      // Start dictation immediately with specified parameters
      await startDictation(
        mode: order == 0 ? DictationMode.sequential : DictationMode.random,
        customQuantity: count,
        wordFileName: wordbookName,
        dictationDirection: mode, // 传递默写方向参数
      );
    } catch (e) {
      _setError('从词书加载单词失败: $e');
    }
  }
  
  Future<void> startDictation({
    required DictationMode mode,
    int? customQuantity,
    String? wordFileName,
    int dictationDirection = 0, // 0: 原文→译文, 1: 译文→原文
  }) async {
    try {
      _setState(DictationState.loading);
      
      // Prepare session words
      _sessionWords = List.from(_words);
      
      if (mode == DictationMode.random) {
        _sessionWords.shuffle();
      }
      
      if (customQuantity != null && customQuantity > 0 && customQuantity < _sessionWords.length) {
        _sessionWords = _sessionWords.take(customQuantity).toList();
      }
      
      // Create session
      _currentSession = DictationSession(
        sessionId: _uuid.v4(),
        wordFileName: wordFileName,
        mode: mode,
        status: SessionStatus.inProgress,
        totalWords: _sessionWords.length,
        startTime: DateTime.now(),
        dictationDirection: dictationDirection,
      );
      
      // Ensure all words have IDs (save to database if needed)
      for (int i = 0; i < _sessionWords.length; i++) {
        if (_sessionWords[i].id == null) {
          final wordId = await _wordService.insertWord(_sessionWords[i]);
          _sessionWords[i] = _sessionWords[i].copyWith(id: wordId);
        }
      }
      
      // Save session to database
      await _dictationService.createSession(_currentSession!);
      
      // Save session words
      for (int i = 0; i < _sessionWords.length; i++) {
        await _dictationService.addWordToSession(
          _currentSession!.sessionId,
          _sessionWords[i].id!,
          i,
        );
      }
      
      _results.clear();
      _showNextWord();
    } catch (e) {
      _setError('开始默写失败: $e');
    }
  }
  
  void _showNextWord() {
    if (_currentSession == null) return;
    
    final index = _currentSession!.currentWordIndex;
    if (index < _sessionWords.length) {
      _currentWord = _sessionWords[index];
      _originalImagePath = null;
      _annotatedImagePath = null;
      _isAnnotationMode = false;
      _setState(DictationState.inProgress);
    } else {
      _completeDictation();
    }
  }
  
  Future<void> submitAnswer() async {
    if (_currentWord == null || _currentSession == null) return;
    
    try {
      _setState(DictationState.showingAnswer);
      // The UI will handle showing the answer and entering annotation mode
    } catch (e) {
      _setError('提交答案失败: $e');
    }
  }
  
  void setOriginalImagePath(String? path) {
    _originalImagePath = path;
    notifyListeners();
  }
  
  void setAnnotatedImagePath(String? path) {
    _annotatedImagePath = path;
    notifyListeners();
  }
  
  void enterAnnotationMode() {
    _isAnnotationMode = true;
    _setState(DictationState.judging);
  }
  
  Future<void> recordResult(bool isCorrect) async {
    if (_currentWord == null || _currentSession == null) return;
    
    try {
      final result = DictationResult(
        sessionId: _currentSession!.sessionId,
        wordId: _currentWord!.id!,
        prompt: _currentWord!.prompt,
        answer: _currentWord!.answer,
        isCorrect: isCorrect,
        originalImagePath: _originalImagePath,
        annotatedImagePath: _annotatedImagePath,
        wordIndex: _currentSession!.currentWordIndex,
        timestamp: DateTime.now(),
      );
      
      _results.add(result);
      
      // Save result to database
      await _dictationService.saveResult(result);
      
      // Update session
      _currentSession = _currentSession!.copyWith(
        currentWordIndex: _currentSession!.currentWordIndex + 1,
        correctCount: isCorrect ? _currentSession!.correctCount + 1 : _currentSession!.correctCount,
        incorrectCount: !isCorrect ? _currentSession!.incorrectCount + 1 : _currentSession!.incorrectCount,
      );
      
      await _dictationService.updateSession(_currentSession!);
      
      _showNextWord();
    } catch (e) {
      _setError('记录结果失败: $e');
    }
  }
  
  Future<void> _completeDictation() async {
    if (_currentSession == null) return;
    
    try {
      _currentSession = _currentSession!.copyWith(
        status: SessionStatus.completed,
        endTime: DateTime.now(),
      );
      
      await _dictationService.updateSession(_currentSession!);
      _setState(DictationState.completed);
    } catch (e) {
      _setError('完成默写失败: $e');
    }
  }
  
  Future<void> retryIncorrectWords() async {
    if (_currentSession == null || incorrectResults.isEmpty) return;
    
    try {
      final incorrectWords = incorrectResults
          .map((result) => _sessionWords.firstWhere(
                (word) => word.id == result.wordId,
              ))
          .toList();
      
      await startDictation(
        mode: DictationMode.retry,
        wordFileName: '错题重做',
      );
      
      _sessionWords = incorrectWords;
      _currentSession = _currentSession!.copyWith(
        isRetrySession: true,
        originalSessionId: _currentSession!.sessionId,
        totalWords: incorrectWords.length,
      );
      
      await _dictationService.updateSession(_currentSession!);
      _showNextWord();
    } catch (e) {
      _setError('重做错题失败: $e');
    }
  }
  
  void nextWord() {
    if (_currentSession == null) return;
    
    final nextIndex = _currentSession!.currentWordIndex + 1;
    _currentSession = _currentSession!.copyWith(
      currentWordIndex: nextIndex,
    );
    
    _showNextWord();
  }
  
  void endSession() {
    if (_currentSession == null) return;
    
    _currentSession = _currentSession!.copyWith(
      status: SessionStatus.completed,
      endTime: DateTime.now(),
    );
    
    _setState(DictationState.completed);
  }
  
  void finishSession() {
    _currentSession = null;
    _currentWord = null;
    _sessionWords.clear();
    _results.clear();
    _originalImagePath = null;
    _annotatedImagePath = null;
    _isAnnotationMode = false;
    _setState(DictationState.idle);
  }
  
  void reset() {
    _currentSession = null;
    _words.clear();
    _sessionWords.clear();
    _results.clear();
    _currentWord = null;
    _originalImagePath = null;
    _annotatedImagePath = null;
    _isAnnotationMode = false;
    _errorMessage = null;
    _setState(DictationState.idle);
  }
  
  void _setState(DictationState newState) {
    _state = newState;
    notifyListeners();
  }
  
  void _setError(String message) {
    _errorMessage = message;
    _setState(DictationState.error);
  }
  
  void clearError() {
    _errorMessage = null;
    if (_state == DictationState.error) {
      _setState(DictationState.idle);
    }
  }
}