/// Append-only transcript of one terminal session.
library;

import 'dart:io';

class SessionLog {
  SessionLog(this.file);

  final File file;
  IOSink? _sink;

  Future<void> open() async {
    await file.parent.create(recursive: true);
    _sink = file.openWrite(mode: FileMode.append);
    _sink!.writeln('\n----- ${DateTime.now().toIso8601String()} -----');
  }

  void write(String data) {
    _sink?.write(data);
  }

  Future<void> close() async {
    final sink = _sink;
    _sink = null;
    if (sink == null) return;
    await sink.flush();
    await sink.close();
  }
}
