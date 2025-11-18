import 'dart:io';

typedef CommandRunner = Future<ProcessResult> Function(
  String, List<String>, {
  String? workingDirectory,
});

class MdictCppBridge {
  static MdictCppBridge? _instance;
  final CommandRunner _runner;
  String? _exePath;
  final Map<String, List<String>> _keyCache = {};

  MdictCppBridge._(this._runner);

  static MdictCppBridge getInstance({CommandRunner? runner}) {
    if (runner != null) {
      _instance = MdictCppBridge._(runner);
    } else {
      _instance ??= MdictCppBridge._(_defaultRunner);
    }
    return _instance!;
  }

  static Future<ProcessResult> _defaultRunner(
    String command,
    List<String> args, {
    String? workingDirectory,
  }) async {
    return await Process.run(
      command,
      args,
      workingDirectory: workingDirectory,
      runInShell: true,
    );
  }

  Future<String?> _detectExePath() async {
    if (_exePath != null) return _exePath;
    try {
      final envPath = Platform.environment['MDICT_CPP_EXE'];
      if (envPath != null && envPath.isNotEmpty) {
        final f = File(envPath);
        if (await f.exists()) {
          _exePath = f.path;
          return _exePath;
        }
      }
      final pr = await _runner('where', ['mydict']);
      if (pr.exitCode == 0) {
        final out = (pr.stdout ?? '').toString().trim();
        if (out.isNotEmpty) {
          final first = out.split(RegExp(r'[\r\n]+')).first.trim();
          if (first.isNotEmpty) {
            _exePath = first;
            return _exePath;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  Future<bool> isAvailable() async {
    final p = await _detectExePath();
    return p != null && p.isNotEmpty;
  }

  Future<String?> queryDefinition(String mdxPath, String key) async {
    final exe = await _detectExePath();
    final cmd = (exe == null || exe.isEmpty) ? 'mydict' : exe;
    try {
      final pr = await _runner(cmd, [mdxPath, key]);
      if (pr.exitCode != 0) return null;
      final out = (pr.stdout ?? '').toString();
      final s = out.trim();
      if (s.isEmpty) return null;
      return s;
    } catch (_) {
      return null;
    }
  }

  Future<List<String>> listKeys(String mdxPath, {bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final cached = _keyCache[mdxPath];
      if (cached != null && cached.isNotEmpty) return cached;
    }
    final exe = await _detectExePath();
    final cmd = (exe == null || exe.isEmpty) ? 'mydict' : exe;
    try {
      final pr = await _runner(cmd, ['-l', mdxPath]);
      if (pr.exitCode != 0) return [];
      final out = (pr.stdout ?? '').toString();
      final lines = out.split(RegExp(r'[\r\n]+')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      if (lines.isNotEmpty) {
        _keyCache[mdxPath] = lines;
      }
      return lines;
    } catch (_) {
      return [];
    }
  }

  Future<String?> readByIndex(String mdxPath, int index) async {
    if (index <= 0) return null;
    final keys = await listKeys(mdxPath);
    if (keys.isEmpty) return null;
    if (index > keys.length) return null;
    final key = keys[index - 1];
    return await queryDefinition(mdxPath, key);
  }
}