/// Session repository - load/save the session tree (profiles + macros),
/// the JTerm equivalent of MobaXterm's .mxtsessions bookmark store.
library;

import '../models/macro.dart';
import '../models/session_profile.dart';
import 'json_store.dart';

class SessionRepository {
  SessionRepository(this.store);

  final JsonStore store;

  List<SessionProfile> sessions = [];
  List<Macro> macros = [];

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
  }

  Future<void> _persist() => store.write({
        'version': 1,
        'sessions': sessions.map((s) => s.toJson()).toList(),
        'macros': macros.map((m) => m.toJson()).toList(),
      });

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
}
