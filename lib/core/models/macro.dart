/// Macro model - a replayable sequence of commands with delays, equivalent to
/// the MobaXterm macro recorder.
library;

class MacroStep {
  MacroStep({required this.command, this.delayMs = 200});

  String command;
  int delayMs;

  Map<String, dynamic> toJson() => {'command': command, 'delayMs': delayMs};

  factory MacroStep.fromJson(Map<String, dynamic> json) => MacroStep(
        command: json['command'] as String,
        delayMs: (json['delayMs'] as num?)?.toInt() ?? 200,
      );
}

class Macro {
  Macro({required this.id, required this.name, required this.steps});

  final String id;
  String name;
  List<MacroStep> steps;

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'steps': steps.map((s) => s.toJson()).toList()};

  factory Macro.fromJson(Map<String, dynamic> json) => Macro(
        id: json['id'] as String,
        name: json['name'] as String,
        steps: (json['steps'] as List<dynamic>)
            .map((e) => MacroStep.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
