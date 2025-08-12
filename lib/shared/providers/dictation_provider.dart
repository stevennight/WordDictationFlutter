import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';

import '../models/word.dart';
import '../models/dictation_session.dart';
import '../models/dictation_result.dart';
import '../utils/path_utils.dart';
import '../../core/services/dictation_service.dart';
import '../../core/services/word_service.dart';
import '../../core/utils/file_hash_utils.dart';

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
  
  // Cached MD5 values to avoid recalculation
  String? _originalImageMd5;
  String? _annotatedImageMd5;
  
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
  int get dictationDirection => _currentSession?.dictationDirection ?? 0;
  
  String? get currentAnswerText {
    if (_currentWord == null || (_state != DictationState.judging)) return null;
    final dictationDirection = _currentSession?.dictationDirection ?? 0;
    return dictationDirection == 0 ? _currentWord!.answer : _currentWord!.prompt;
  }
  
  String get currentPromptText {
    if (_currentWord == null) return '';
    final dictationDirection = _currentSession?.dictationDirection ?? 0;
    return dictationDirection == 0 ? _currentWord!.prompt : _currentWord!.answer;
  }
  
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
        expectedTotalWords: _sessionWords.length,
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
      
      // 不在开始时保存session，改为在完成或退出时保存
      // Session will be saved only when completing or exiting with progress
      
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
  
  Future<void> setOriginalImagePath(String? path) async {
    _originalImagePath = path;
    
    // 立即计算MD5值并缓存，避免后续文件变化导致的问题
    if (path != null && path.isNotEmpty) {
      try {
        // 将相对路径转换为绝对路径
        final absolutePath = await _convertToAbsolutePath(path);
        final file = File(absolutePath);
        if (await file.exists()) {
          _originalImageMd5 = await FileHashUtils.calculateFileMd5Async(file);
          debugPrint('原始图片MD5已计算并缓存: $_originalImageMd5 (路径: $absolutePath)');
        } else {
          _originalImageMd5 = null;
          debugPrint('原始图片文件不存在，无法计算MD5: $absolutePath (相对路径: $path)');
        }
      } catch (e) {
        _originalImageMd5 = null;
        debugPrint('计算原始图片MD5失败: $e');
      }
    } else {
      _originalImageMd5 = null;
    }
    
    notifyListeners();
  }
  
  Future<void> setAnnotatedImagePath(String? path) async {
    _annotatedImagePath = path;
    
    // 立即计算MD5值并缓存，避免后续文件变化导致的问题
    if (path != null && path.isNotEmpty) {
      try {
        // 将相对路径转换为绝对路径
        final absolutePath = await _convertToAbsolutePath(path);
        final file = File(absolutePath);
        if (await file.exists()) {
          _annotatedImageMd5 = await FileHashUtils.calculateFileMd5Async(file);
          debugPrint('批改图片MD5已计算并缓存: $_annotatedImageMd5 (路径: $absolutePath)');
        } else {
          _annotatedImageMd5 = null;
          debugPrint('批改图片文件不存在，无法计算MD5: $absolutePath (相对路径: $path)');
        }
      } catch (e) {
        _annotatedImageMd5 = null;
        debugPrint('计算批改图片MD5失败: $e');
      }
    } else {
      _annotatedImageMd5 = null;
    }
    
    notifyListeners();
  }
  
  void enterAnnotationMode() {
    _isAnnotationMode = true;
    _setState(DictationState.judging);
  }
  
  Future<void> recordResult(bool isCorrect) async {
    if (_currentWord == null || _currentSession == null) return;
    
    try {
      // 使用缓存的MD5值，避免重复计算
      // 如果缓存值不存在，则尝试重新计算（兜底逻辑）
      String? originalImageMd5 = _originalImageMd5;
      String? annotatedImageMd5 = _annotatedImageMd5;
      
      // 兜底逻辑：如果缓存的MD5为空但文件路径存在，尝试重新计算
      if (originalImageMd5 == null && _originalImagePath != null && _originalImagePath!.isNotEmpty) {
        try {
          final absolutePath = await _convertToAbsolutePath(_originalImagePath!);
          final originalFile = File(absolutePath);
          if (await originalFile.exists()) {
            originalImageMd5 = await FileHashUtils.calculateFileMd5Async(originalFile);
            debugPrint('原始图片MD5兜底计算: $originalImageMd5');
          }
        } catch (e) {
          debugPrint('兜底计算原始图片MD5失败: $e');
        }
      }
      
      if (annotatedImageMd5 == null && _annotatedImagePath != null && _annotatedImagePath!.isNotEmpty) {
        try {
          final absolutePath = await _convertToAbsolutePath(_annotatedImagePath!);
          final annotatedFile = File(absolutePath);
          if (await annotatedFile.exists()) {
            annotatedImageMd5 = await FileHashUtils.calculateFileMd5Async(annotatedFile);
            debugPrint('批改图片MD5兜底计算: $annotatedImageMd5');
          }
        } catch (e) {
          debugPrint('兜底计算批改图片MD5失败: $e');
        }
      }
      
      final result = DictationResult(
        sessionId: _currentSession!.sessionId,
        wordId: _currentWord!.id!,
        prompt: _currentWord!.prompt,
        answer: _currentWord!.answer,
        isCorrect: isCorrect,
        originalImagePath: _originalImagePath,
        annotatedImagePath: _annotatedImagePath,
        originalImageMd5: originalImageMd5,
        annotatedImageMd5: annotatedImageMd5,
        wordIndex: _currentSession!.currentWordIndex,
        timestamp: DateTime.now(),
        // Store word details as snapshot to avoid foreign key issues
        // 存储单词详细信息快照，实现数据快照策略：
        // 1. 保证历史记录独立性 - 原单词信息变更不影响此记录
        // 2. 避免外键约束问题 - 原单词删除不影响此记录
        // 3. 提升查询性能 - 无需关联查询即可获取完整信息
        category: _currentWord!.category,
        partOfSpeech: _currentWord!.partOfSpeech,
        level: _currentWord!.level,
      );
      
      _results.add(result);
      
      // 不在此处保存result，改为在完成或退出时统一保存
      
      // Update session - increment index and counts
      _currentSession = _currentSession!.copyWith(
        currentWordIndex: _currentSession!.currentWordIndex + 1,
        correctCount: isCorrect ? _currentSession!.correctCount + 1 : _currentSession!.correctCount,
        incorrectCount: !isCorrect ? _currentSession!.incorrectCount + 1 : _currentSession!.incorrectCount,
      );
      
      // 不在此处更新session到数据库
      
      // Show next word without incrementing index again
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
      
      // 完成默写时保存session到历史记录
      await _saveSessionToHistory();
      _setState(DictationState.completed);
    } catch (e) {
      _setError('完成默写失败: $e');
    }
  }
  
  /// 保存session到历史记录
  Future<void> _saveSessionToHistory() async {
    if (_currentSession == null) return;
    
    try {
      // 确保所有单词都有ID
      for (int i = 0; i < _sessionWords.length; i++) {
        if (_sessionWords[i].id == null) {
          final wordId = await _wordService.insertWord(_sessionWords[i]);
          _sessionWords[i] = _sessionWords[i].copyWith(id: wordId);
        }
      }
      
      // 保存session到数据库
      await _dictationService.createSession(_currentSession!);
      
      // Note: session_words table operations removed as no longer needed
      
      // 保存所有结果
      for (final result in _results) {
        await _dictationService.saveResult(result);
      }
    } catch (e) {
      debugPrint('保存session到历史记录失败: $e');
      rethrow;
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
        expectedTotalWords: incorrectWords.length,
      );
      
      await _dictationService.updateSession(_currentSession!);
      _showNextWord();
    } catch (e) {
      _setError('重做错题失败: $e');
    }
  }
  
  void nextWord() {
    if (_currentSession == null) return;
    
    // Don't increment index here as it's already incremented in recordResult
    _showNextWord();
  }
  
  Future<void> endSession() async {
    if (_currentSession == null) return;
    
    try {
      // 如果已经默写了至少1个单词，保存到历史记录并显示结果
      if (_results.isNotEmpty) {
        _currentSession = _currentSession!.copyWith(
          status: SessionStatus.incomplete, // 标记为未完成
          endTime: DateTime.now(),
          totalWords: _results.length, // 实际完成的数量
          // 保持expectedTotalWords不变，这样历史记录能正确显示预期数量
        );
        
        // 保存到历史记录
        await _saveSessionToHistory();
        _setState(DictationState.completed); // 显示结果界面
      } else {
        // 没有默写任何单词，直接结束不保存
        _setState(DictationState.idle);
      }
    } catch (e) {
      _setError('结束默写失败: $e');
    }
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
    
    // 清理缓存的MD5值
    _originalImageMd5 = null;
    _annotatedImageMd5 = null;
    
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

  // Copying mode methods
  void initializeCopying(List<Word> words, int startIndex) {
    _words = words;
    _sessionWords = List.from(words);
    _currentSession = DictationSession(
      sessionId: _uuid.v4(),
      mode: DictationMode.sequential,
      status: SessionStatus.inProgress,
      totalWords: words.length,
      expectedTotalWords: words.length,
      currentWordIndex: startIndex,
      startTime: DateTime.now(),
      dictationDirection: 0,
    );
    _currentWord = _sessionWords[startIndex];
    _setState(DictationState.inProgress);
  }

  void goToNextWord() {
    if (_currentSession == null) return;
    
    final nextIndex = _currentSession!.currentWordIndex + 1;
    if (nextIndex < _sessionWords.length) {
      _currentSession = _currentSession!.copyWith(
        currentWordIndex: nextIndex,
      );
      _currentWord = _sessionWords[nextIndex];
      // 重置状态到默写模式
      _originalImagePath = null;
      _annotatedImagePath = null;
      _isAnnotationMode = false;
      _setState(DictationState.inProgress);
      clearCanvas();
    } else {
      _completeDictation();
    }
  }

  void goToPreviousWord() {
    if (_currentSession == null) return;
    
    final prevIndex = _currentSession!.currentWordIndex - 1;
    if (prevIndex >= 0) {
      _currentSession = _currentSession!.copyWith(
        currentWordIndex: prevIndex,
      );
      _currentWord = _sessionWords[prevIndex];
      clearCanvas();
      notifyListeners();
    }
  }

  // Canvas methods
  void clearCanvas() {
    // This method will be called to clear the handwriting canvas
    // The actual canvas clearing will be handled by the canvas widget
    
    // 清理图片路径和缓存的MD5值
    _originalImagePath = null;
    _annotatedImagePath = null;
    _originalImageMd5 = null;
    _annotatedImageMd5 = null;
    
    notifyListeners();
  }

  // State management methods
  void setState(DictationState newState) {
    _state = newState;
    notifyListeners();
  }

  // Result modification methods
  void updateResult(int wordIndex, bool isCorrect, {String? annotatedImagePath}) {
    // 查找现有结果
    final existingResultIndex = _results.indexWhere(
      (result) => result.wordIndex == wordIndex
    );
    
    if (existingResultIndex != -1) {
      // 更新现有结果
      final existingResult = _results[existingResultIndex];
      final updatedResult = existingResult.copyWith(
        isCorrect: isCorrect,
        annotatedImagePath: annotatedImagePath ?? existingResult.annotatedImagePath,
        timestamp: DateTime.now(),
      );
      _results[existingResultIndex] = updatedResult;
      
      // 更新会话统计
      _updateSessionCounts();
      notifyListeners();
    }
  }

  void _updateSessionCounts() {
    if (_currentSession == null) return;
    
    int correctCount = 0;
    int incorrectCount = 0;
    
    for (final result in _results) {
      if (result.isCorrect) {
        correctCount++;
      } else {
        incorrectCount++;
      }
    }
    
    _currentSession = _currentSession!.copyWith(
      correctCount: correctCount,
      incorrectCount: incorrectCount,
    );
  }

  /// 将相对路径转换为绝对路径
  /// 处理数据库中存储的正斜杠路径，转换为系统适配的绝对路径
  Future<String> _convertToAbsolutePath(String relativePath) async {
    try {
      // 如果已经是绝对路径，直接返回
      if (path.isAbsolute(relativePath)) {
        return relativePath;
      }
      
      // Use unified path management
      final appDir = await PathUtils.getAppDirectory();
      
      // 将数据库中的正斜杠路径转换为系统路径分隔符
      // 使用path.joinAll来处理路径片段，确保使用正确的系统分隔符
      final pathSegments = relativePath.split('/');
      final absolutePath = path.joinAll([appDir.path, ...pathSegments]);
      debugPrint('Path conversion: $relativePath -> $absolutePath (appDir: ${appDir.path})');
      return absolutePath;
    } catch (e) {
      debugPrint('转换绝对路径失败: $e');
      // 如果转换失败，返回原路径
      return relativePath;
    }
  }
}