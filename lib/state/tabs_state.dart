/// Open-tab management: lifecycle, activation, broadcast groups and the
/// SFTP panel binding (the active SSH tab drives the SFTP sidebar).
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../core/models/session_profile.dart';
import '../core/terminal/local_pty_session.dart';
import '../core/terminal/ssh_terminal_session.dart';
import '../core/terminal/terminal_session.dart';
import '../core/terminal/telnet_terminal_session.dart';
import 'app_state.dart';

class TabEntry {
  TabEntry({
    required this.id,
    required this.session,
    required this.title,
  });

  final String id;
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

    final TerminalSessionBase session;
    switch (profile.type) {
      case SessionType.ssh:
        session = SshTerminalSession(profile, app.services);
      case SessionType.localShell:
        session = LocalPtySession(profile);
      case SessionType.telnet:
        session = TelnetTerminalSession(profile);
      case SessionType.serial:
        throw UnsupportedError(
            'Serial sessions require the libserialport plugin (planned)');
    }

    final tab = TabEntry(
      id: 'tab-${_seq++}',
      session: session,
      title: profile.name,
    );

    tab._eventSub = session.events.listen((e) {
      if (e is SessionStatusChanged) {
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
    activeId = id;
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

  @override
  void dispose() {
    for (final t in tabs) {
      t._eventSub?.cancel();
      unawaited(t.session.dispose());
    }
    super.dispose();
  }
}
