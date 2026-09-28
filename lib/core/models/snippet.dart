/// A one-shot command snippet, the short form of a MobaXterm macro.
library;

class Snippet {
  Snippet({required this.id, required this.name, required this.command});

  final String id;
  String name;
  String command;

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'command': command};

  factory Snippet.fromJson(Map<String, dynamic> json) => Snippet(
        id: json['id'] as String,
        name: json['name'] as String,
        command: json['command'] as String? ?? '',
      );
}
