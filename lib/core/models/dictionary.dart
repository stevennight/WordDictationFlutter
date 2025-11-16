class Dictionary {
  final String name;
  final String path;

  Dictionary({required this.name, required this.path});

  Map<String, dynamic> toJson() => {
        'name': name,
        'path': path,
      };

  factory Dictionary.fromJson(Map<String, dynamic> json) => Dictionary(
        name: json['name'] as String,
        path: json['path'] as String,
      );
}