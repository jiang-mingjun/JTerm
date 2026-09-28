/// Open-tab management: lifecycle, activation, broadcast groups and the
/// SFTP panel binding (the active SSH tab drives the SFTP sidebar).
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../core/models/macro.dart';
import '../core/models/session_profile.dart';
import '../core/terminal/local_pty_session.dart';
import '../core/terminal/serial_terminal_session.dart';
import '../core/terminal/ssh_terminal_session.dart';
import '../core/terminal/terminal_session.dart';
import '../core/terminal/telnet_terminal_session.dart';
import 'app_state.dart';

enum PaneSplit { none, horizontal, vertical }

class TabEntry {
  TabEntry({
    required this.id,
    required this.session,
    required this.title,
  });

  final String id;
  final GlobalKey pageKey = GlobalKey();
  final TerminalSessionBase session;
  String title;
  StreamSubscription? _eventSub;
}

class TabsState extends ChangeNotifier {
  TabsState(this.app);

  final AppState app;

  final List<TabEntry> tabs = [];
  String? activeId;
  int _seq = 0;

  final Set<String> broadcastIds = {};
  bool get broadcastActive => broadcastIds.isNotEmpty;

  TabEntry? get active =>
      tabs.where((t) => t.id == activeId).firstOrNull;

  SshTerminalSession? get activeSsh {
    final t = active;
    return t?.session is SshTerminalSession ? t!.session as SshTerminalSession : null;
  }

  bool showSftpPanel = true;

  PaneSplit split = PaneSplit.none;
  String? splitTabId;

  bool recordingMacro = false;
  final List<MacroStep> _recorded = [];
  String _recordLine = '';

  TabEntry open(SessionProfile profile) {
    // Reconnect if the same profile is already open in a tab.
    final existing =
        tabs.where((t) => t.session.profile.id == profile.id).firstOrNull;
    if (existing != null) {
      activate(existing.id);
      if (existing.session.status == SessionStatus.disconnected ||
          existing.session.status == SessionStatus.failed) {
        unawaited(existing.session.connect());
      }
      return existing;
    }

    final maxLines = app.settings.scrollbackLines.clamp(1000, 200000);
    final TerminalSessionBase session;
    switch (profile.type) {
      case SessionType.ssh:
        session = SshTerminalSession(profile, app.services, maxLines: maxLines);
      case SessionType.localShell:
        session = LocalPtySession(profile, maxLines: maxLines);
      case SessionType.telnet:
        session = TelnetTerminalSession(profile, maxLines: maxLines);
      case SessionType.serial:
        session = SerialTerminalSession(profile, maxLines: maxLines);
    }
    session.loggingEnabled = profile.logSession || app.settings.logSessions;
    session.logDirectory = app.services.logDirectory;
    session.onUserInput = _recordInput;

    final tab = TabEntry(
      id: 'tab-${_seq++}',
      session: session,
      title: profile.name,
    );

    tab._eventSub = session.events.listen((e) {
      if (e is SessionStatusChanged || e is SessionCwdChanged) {
        notifyListeners();
      } else if (e is SessionTitleChanged) {
        tab.title = e.title;
        notifyListeners();
      }
    });

    session.terminal.onTitleChange = (t) {
      if (t.isNotEmpty) {
        tab.title = t;
        notifyListeners();
      }
    };

    tabs.add(tab);
    activeId = tab.id;
    if (profile.type == SessionType.ssh) {
      // The SFTP sidebar follows newly opened SSH sessions, MobaXterm style.
      showSftpPanel = profile.autoOpenSftp;
    }
    notifyListeners();
    unawaited(session.connect());
    app.repo.touch(profile.id);
    return tab;
  }

  void activate(String id) {
    if (split != PaneSplit.none && id == splitTabId && id != activeId) {
      splitTabId = activeId;
    }
    activeId = id;
    notifyListeners();
  }

  void duplicate(String id) {
    final tab = tabs.where((t) => t.id == id).firstOrNull;
    if (tab == null) return;
    final clone = tab.session.profile.copyWith();
    clone.id = '${clone.id}#${DateTime.now().millisecondsSinceEpoch}';
    open(clone);
  }

  void rename(String id, String title) {
    final tab = tabs.where((t) => t.id == id).firstOrNull;
    if (tab == null || title.trim().isEmpty) return;
    tab.title = title.trim();
    notifyListeners();
  }

  void setSplit(PaneSplit mode, String tabId) {
    if (mode == PaneSplit.none) {
      split = PaneSplit.none;
      splitTabId = null;
      notifyListeners();
      return;
    }
    if (tabs.length < 2 && tabId == activeId) {
      split = mode;
      splitTabId = null;
      notifyListeners();
      return;
    }
    split = mode;
    if (tabId != activeId) {
      splitTabId = tabId;
    } else {
      splitTabId = tabs.where((t) => t.id != activeId).firstOrNull?.id;
    }
    notifyListeners();
  }

  void close(String id) {
    final i = tabs.indexWhere((t) => t.id == id);
    if (i < 0) return;
    final tab = tabs.removeAt(i);
    broadcastIds.remove(id);
    tab._eventSub?.cancel();
    unawaited(tab.session.dispose());
    if (activeId == id) {
      activeId = tabs.isEmpty ? null : tabs[i.clamp(0, tabs.length - 1)].id;
    }
    notifyListeners();
  }

  void next() {
    if (tabs.length < 2) return;
    final i = tabs.indexWhere((t) => t.id == activeId);
    activate(tabs[(i + 1) % tabs.length].id);
  }

  void previous() {
    if (tabs.length < 2) return;
    final i = tabs.indexWhere((t) => t.id == activeId);
    activate(tabs[(i - 1 + tabs.length) % tabs.length].id);
  }

  // ------------------------------------------------------------------
  // Broadcast input to multiple sessions
  // ------------------------------------------------------------------
  void toggleBroadcast(String id) {
    if (broadcastIds.contains(id)) {
      broadcastIds.remove(id);
      _rewireBroadcast();
    } else {
      broadcastIds.add(id);
      _rewireBroadcast();
    }
    notifyListeners();
  }

  void _rewireBroadcast() {
    for (final t in tabs) {
      if (broadcastIds.contains(t.id) && broadcastIds.length > 1) {
        t.session.onInputHook = (data) {
          for (final other in tabs) {
            if (other.id != t.id && broadcastIds.contains(other.id)) {
              other.session.writeInput(data);
            }
          }
        };
      } else {
        t.session.onInputHook = null;
      }
    }
  }

  /// Sends one macro step to the active session (or all broadcast sessions).
  void sendCommand(String command) {
    final targets = broadcastIds.isEmpty
        ? [if (active != null) active!.id]
        : broadcastIds.toList();
    for (final id in targets) {
      tabs
          .where((t) => t.id == id)
          .firstOrNull
          ?.session
          .writeInput(command);
    }
  }

  void toggleSftpPanel() {
    showSftpPanel = !showSftpPanel;
    notifyListeners();
  }

  void beginRecording() {
    _recorded.clear();
    _recordLine = '';
    recordingMacro = true;
    notifyListeners();
  }

  List<MacroStep> stopRecording() {
    recordingMacro = false;
    if (_recordLine.isNotEmpty) {
      _recorded.add(MacroStep(command: _recordLine));
      _recordLine = '';
    }
    final steps = List<MacroStep>.from(_recorded);
    _recorded.clear();
    notifyListeners();
    return steps;
  }

  void _recordInput(String data) {
    if (!recordingMacro) return;
    for (final rune in data.runes) {
      if (rune == 13 || rune == 10) {
        if (_recordLine.isNotEmpty) {
          _recorded.add(MacroStep(command: _recordLine));
          _recordLine = '';
        }
      } else if (rune == 127 || rune == 8) {
        if (_recordLine.isNotEmpty) {
          _recordLine = _recordLine.substring(0, _recordLine.length - 1);
        }
      } else if (rune >= 32) {
        _recordLine += String.fromCharCode(rune);
      }
    }
  }

  @override
  void dispose() {
    for (final t in tabs) {
      t._eventSub?.cancel();
      unawaited(t.session.dispose());
    }
    super.dispose();
  }
}
