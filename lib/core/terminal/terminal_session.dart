/// Terminal session abstraction - one instance drives exactly one tab.
///
/// The [Terminal] (xterm.dart core) is platform independent; subclasses wire
/// it to SSH / local PTY / telnet / serial transports.
library;

import 'dart:async';

import 'package:xterm/xterm.dart';

import '../models/session_profile.dart';

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

/// Base class of every live terminal session.
abstract class TerminalSessionBase {
  TerminalSessionBase(this.profile);

  final SessionProfile profile;
  final Terminal terminal = Terminal(maxLines: 10000);

  final _events = StreamController<SessionEvent>.broadcast();
  Stream<SessionEvent> get events => _events.stream;

  SessionStatus status = SessionStatus.disconnected;
  String failMessage = '';

  /// Display title of the tab (usually set via OSC 0/2 escape sequence).
  String title = '';

  void emitStatus(SessionStatus s, [String? message]) {
    status = s;
    if (s == SessionStatus.failed && message != null) failMessage = message;
    _events.add(SessionStatusChanged(s, message));
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

  /// Sends raw input straight into the transport (broadcast / macro replay).
  /// Unlike [onTerminalOutput] this bypasses the local echo and hook chain.
  void writeInput(String data);

  Future<void> resize(int cols, int rows);

  Future<void> connect();

  Future<void> disconnect();

  /// Write a raw string into the terminal display (used by macros/broadcast).
  void display(String text) => terminal.write(text);

  Future<void> dispose() async {
    await disconnect();
    await _events.close();
  }
}
