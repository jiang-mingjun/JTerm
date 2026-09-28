/// Session repository - load/save the session tree (profiles + macros),
/// the JTerm equivalent of MobaXterm's .mxtsessions bookmark store.
library;

import '../models/macro.dart';
import '../models/session_profile.dart';
import '../models/snippet.dart';
import 'json_store.dart';

class SessionRepository {
  SessionRepository(this.store);

  final JsonStore store;

  /// Fired after every successful write so the UI can rebuild.
  void Function()? onChanged;

  List<SessionProfile> sessions = [];
  List<Macro> macros = [];
  List<Snippet> snippets = [];

  /// Group name -> children groups (derived from the '/'-separated group path).
  Set<String> get groups =>
      sessions.map((s) => s.group).where((g) => g.isNotEmpty).toSet();

  Future<void> load() async {
    final data = await store.read();
    if (data == null) return;
    sessions = (data['sessions'] as List<dynamic>? ?? [])
        .map((e) => SessionProfile.fromJson(e as Map<String, dynamic>))
        .toList();
    macros = (data['macros'] as List<dynamic>? ?? [])
        .map((e) => Macro.fromJson(e as Map<String, dynamic>))
        .toList();
    snippets = (data['snippets'] as List<dynamic>? ?? [])
        .map((e) => Snippet.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Map<String, dynamic> exportBundle() => {
        'version': 1,
        'sessions': sessions.map((s) => s.toJson()).toList(),
        'macros': macros.map((m) => m.toJson()).toList(),
        'snippets': snippets.map((s) => s.toJson()).toList(),
      };

  Future<int> importBundle(Map<String, dynamic> data) async {
    var count = 0;
    final stamp = DateTime.now().millisecondsSinceEpoch;
    for (final raw in data['sessions'] as List<dynamic>? ?? []) {
      final profile = SessionProfile.fromJson(raw as Map<String, dynamic>);
      if (byId(profile.id) != null) {
        profile.id = '${profile.id}-$stamp-$count';
        profile.name = '${profile.name} (导入)';
      }
      sessions.add(profile);
      count++;
    }
    for (final raw in data['macros'] as List<dynamic>? ?? []) {
      final macro = Macro.fromJson(raw as Map<String, dynamic>);
      if (macros.any((m) => m.id == macro.id)) {
        continue;
      }
      macros.add(macro);
      count++;
    }
    await _persist();
    return count;
  }

  Future<void> _persist() async {
    await store.write({
      'version': 1,
      'sessions': sessions.map((s) => s.toJson()).toList(),
      'macros': macros.map((m) => m.toJson()).toList(),
      'snippets': snippets.map((s) => s.toJson()).toList(),
    });
    onChanged?.call();
  }

  Future<void> upsert(SessionProfile p) async {
    final i = sessions.indexWhere((s) => s.id == p.id);
    if (i >= 0) {
      sessions[i] = p;
    } else {
      sessions.add(p);
    }
    await _persist();
  }

  Future<void> remove(String id) async {
    sessions.removeWhere((s) => s.id == id);
    await _persist();
  }

  Future<void> touch(String id) async {
    final s = byId(id);
    if (s != null) {
      s.lastUsedMs = DateTime.now().millisecondsSinceEpoch;
      await _persist();
    }
  }

  SessionProfile? byId(String id) {
    for (final s in sessions) {
      if (s.id == id) return s;
    }
    return null;
  }

  List<SessionProfile> byGroup(String group) => sessions
      .where((s) => s.group == group)
      .toList()
    ..sort((a, b) => a.name.compareTo(b.name));

  Future<void> saveMacro(Macro m) async {
    final i = macros.indexWhere((x) => x.id == m.id);
    if (i >= 0) {
      macros[i] = m;
    } else {
      macros.add(m);
    }
    await _persist();
  }

  Future<void> deleteMacro(String id) async {
    macros.removeWhere((m) => m.id == id);
    await _persist();
  }

  Future<void> saveSnippet(Snippet s) async {
    final i = snippets.indexWhere((x) => x.id == s.id);
    if (i >= 0) {
      snippets[i] = s;
    } else {
      snippets.add(s);
    }
    await _persist();
  }

  Future<void> deleteSnippet(String id) async {
    snippets.removeWhere((s) => s.id == id);
    await _persist();
  }
}
