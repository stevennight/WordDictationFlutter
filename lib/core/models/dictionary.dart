class Dictionary {
  final String name;
  final String path;
  final bool enabledForAI;

  Dictionary({required this.name, required this.path, this.enabledForAI = true});

  Map<String, dynamic> toJson() => {
        'name': name,
        'path': path,
        'enabledForAI': enabledForAI,
      };

  factory Dictionary.fromJson(Map<String, dynamic> json) {
    final v = json['enabledForAI'];
    bool enabled = true;
    if (v is bool) {
      enabled = v;
    } else if (v is String) {
      final s = v.toLowerCase();
      if (s == 'true' || s == '1') {
        enabled = true;
      } else if (s == 'false' || s == '0') {
        enabled = false;
      }
    } else if (v is num) {
      enabled = v != 0;
    }
    return Dictionary(
      name: json['name'] as String,
      path: json['path'] as String,
      enabledForAI: enabled,
    );
  }
}