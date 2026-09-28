/// Terminal session abstraction - one instance drives exactly one tab.
///
/// The [Terminal] (xterm.dart core) is platform independent; subclasses wire
/// it to SSH / local PTY / telnet / serial transports.
library;

import 'dart:async';
import 'dart:io';

import 'package:xterm/xterm.dart';

import '../models/session_profile.dart';
import 'session_log.dart';

enum SessionStatus {
  connecting,
  connected,
  disconnected,
  failed,
  reconnecting,
}

sealed class SessionEvent {
  const SessionEvent();
}

class SessionStatusChanged extends SessionEvent {
  const SessionStatusChanged(this.status, [this.message]);

  final SessionStatus status;
  final String? message;
}

class SessionTitleChanged extends SessionEvent {
  const SessionTitleChanged(this.title);

  final String title;
}

class SessionCwdChanged extends SessionEvent {
  const SessionCwdChanged(this.path);

  final String path;
}

/// Base class of every live terminal session.
abstract class TerminalSessionBase {
  TerminalSessionBase(this.profile, {int maxLines = 10000})
      : terminal = Terminal(maxLines: maxLines);

  final SessionProfile profile;
  final Terminal terminal;

  final _events = StreamController<SessionEvent>.broadcast();
  Stream<SessionEvent> get events => _events.stream;

  SessionStatus status = SessionStatus.disconnected;
  String failMessage = '';

  /// Display title of the tab (usually set via OSC 0/2 escape sequence).
  String title = '';

  /// Remote working directory, when the transport can report one.
  String remoteCwd = '';

  int columns = 80;
  int rows = 24;

  /// How many times an automatic reconnect has been attempted for this drop.
  int reconnectAttempt = 0;

  bool loggingEnabled = false;
  String logDirectory = '';
  SessionLog? log;
  String? logPath;

  void emitStatus(SessionStatus s, [String? message]) {
    status = s;
    if (message != null) failMessage = message;
    _events.add(SessionStatusChanged(s, message));
  }

  void emitCwd(String path) {
    if (path.isEmpty || path == remoteCwd) return;
    remoteCwd = path;
    _events.add(SessionCwdChanged(path));
  }

  void noteViewport(int cols, int rows) {
    columns = cols;
    rows = rows;
  }

  Future<void> ensureLog() async {
    if (!loggingEnabled || logDirectory.isEmpty || log != null) return;
    final safe = profile.name.replaceAll(RegExp(r'[^\w.\-]+'), '_');
    final stamp = DateTime.now().toIso8601String().replaceAll(':', '');
    final file = File('$logDirectory/$safe-$stamp.log');
    final sessionLog = SessionLog(file);
    await sessionLog.open();
    log = sessionLog;
    logPath = file.path;
  }

  void paint(String data) {
    log?.write(data);
    terminal.write(data);
  }

  /// Announce a new tab title (usually from an OSC 0/2 escape sequence).
  void emitTitle(String t) {
    title = t;
    _events.add(SessionTitleChanged(t));
  }

  /// Bytes typed in the terminal view. Must be delivered to the transport.
  void onTerminalOutput(String data);

  /// Optional interceptor invoked for every key the user types in this
  /// terminal. Used for multi-session broadcasting.
  void Function(String data)? onInputHook;

  /// Fired for keys typed in this terminal, before broadcast forwarding.
  void Function(String data)? onUserInput;

  /// Sends raw input straight into the transport (broadcast / macro replay).
  /// Unlike [handleUserInput] this bypasses the local echo and hook chain.
  void writeInput(String data);

  /// Keys typed into the terminal view.
  void handleUserInput(String data) {
    onUserInput?.call(data);
    onInputHook?.call(data);
    writeInput(data);
  }

  Future<void> resize(int cols, int rows);

  Future<void> connect();

  Future<void> disconnect();

  /// Write a raw string into the terminal display (used by macros/broadcast).
  void display(String text) => terminal.write(text);

  Future<void> dispose() async {
    await disconnect();
    await log?.close();
    log = null;
    await _events.close();
  }
}
