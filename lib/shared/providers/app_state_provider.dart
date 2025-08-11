import 'package:flutter/foundation.dart';

class AppStateProvider extends ChangeNotifier {
  bool _isDictationMode = false;
  bool _isFullscreen = false;
  String? _currentWordFileName;
  int _totalWords = 0;
  int _currentWordIndex = 0;
  
  // 词书状态管理
  int _wordbookUpdateCounter = 0;
  
  // Getters
  bool get isDictationMode => _isDictationMode;
  bool get isFullscreen => _isFullscreen;
  String? get currentWordFileName => _currentWordFileName;
  int get totalWords => _totalWords;
  int get currentWordIndex => _currentWordIndex;
  int get wordbookUpdateCounter => _wordbookUpdateCounter;
  
  // Progress calculation
  double get progress {
    if (_totalWords == 0) return 0.0;
    return (_currentWordIndex + 1) / _totalWords;
  }
  
  String get progressText {
    if (_totalWords == 0) return '0/0';
    return '${_currentWordIndex + 1}/$_totalWords';
  }
  
  // Actions
  void enterDictationMode({
    required String wordFileName,
    required int totalWords,
  }) {
    _isDictationMode = true;
    _currentWordFileName = wordFileName;
    _totalWords = totalWords;
    _currentWordIndex = 0;
    notifyListeners();
  }
  
  void exitDictationMode() {
    _isDictationMode = false;
    _currentWordFileName = null;
    _totalWords = 0;
    _currentWordIndex = 0;
    notifyListeners();
  }
  
  void updateCurrentWordIndex(int index) {
    _currentWordIndex = index;
    notifyListeners();
  }
  
  void nextWord() {
    if (_currentWordIndex < _totalWords - 1) {
      _currentWordIndex++;
      notifyListeners();
    }
  }
  
  void previousWord() {
    if (_currentWordIndex > 0) {
      _currentWordIndex--;
      notifyListeners();
    }
  }
  
  void toggleFullscreen() {
    _isFullscreen = !_isFullscreen;
    notifyListeners();
  }
  
  void setFullscreen(bool fullscreen) {
    _isFullscreen = fullscreen;
    notifyListeners();
  }
  
  // 通知词书数据已更新
  void notifyWordbookUpdated() {
    _wordbookUpdateCounter++;
    notifyListeners();
  }
  
  // Reset all state
  void reset() {
    _isDictationMode = false;
    _isFullscreen = false;
    _currentWordFileName = null;
    _totalWords = 0;
    _currentWordIndex = 0;
    notifyListeners();
  }
}