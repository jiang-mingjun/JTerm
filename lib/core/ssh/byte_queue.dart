/// Incremental reader over a byte stream. Used by the SOCKS5 handshake and
/// the OpenSSH agent client, where messages arrive in arbitrary chunks.
library;

import 'dart:async';
import 'dart:math' show min;
import 'dart:typed_data';

class ByteQueue {
  ByteQueue(Stream<Uint8List> stream) {
    _sub = stream.listen(
      _onData,
      onError: (Object error) {
        _error = error;
        _wake();
        _live?.addError(error);
      },
      onDone: () {
        _done = true;
        _wake();
        _live?.close();
      },
    );
  }

  final List<Uint8List> _chunks = [];
  int _chunk = 0;
  int _offset = 0;
  Completer<void>? _pending;
  bool _done = false;
  bool _released = false;
  Object? _error;
  StreamController<Uint8List>? _live;
  late final StreamSubscription<Uint8List> _sub;

  void _onData(Uint8List chunk) {
    if (_released) {
      _live?.add(chunk);
      return;
    }
    _chunks.add(chunk);
    _wake();
  }

  void _wake() {
    final pending = _pending;
    _pending = null;
    if (pending != null && !pending.isCompleted) pending.complete();
  }

  bool _hasByte() {
    while (_chunk < _chunks.length && _offset >= _chunks[_chunk].length) {
      _chunk++;
      _offset = 0;
    }
    return _chunk < _chunks.length;
  }

  Future<Uint8List> take(int count) async {
    final out = Uint8List(count);
    var filled = 0;
    while (filled < count) {
      if (!_hasByte()) {
        if (_error != null) throw _error!;
        if (_done) throw StateError('连接在读完数据前关闭');
        _pending = Completer<void>();
        await _pending!.future;
        continue;
      }
      final current = _chunks[_chunk];
      final n = min(count - filled, current.length - _offset);
      out.setRange(filled, filled + n, current, _offset);
      filled += n;
      _offset += n;
      if (_offset >= current.length) {
        _chunk++;
        _offset = 0;
      }
    }
    return out;
  }

  Uint8List unread() {
    final builder = BytesBuilder(copy: false);
    if (_chunk < _chunks.length) {
      builder.add(_chunks[_chunk].sublist(_offset));
      for (var i = _chunk + 1; i < _chunks.length; i++) {
        builder.add(_chunks[i]);
      }
    }
    _chunk = _chunks.length;
    _offset = 0;
    return builder.takeBytes();
  }

  /// After the handshake, leftover bytes and every later chunk are exposed as
  /// the SSH transport stream. The underlying subscription stays alive.
  Stream<Uint8List> detachStream() {
    _released = true;
    final controller = StreamController<Uint8List>();
    _live = controller;
    final left = unread();
    scheduleMicrotask(() {
      if (left.isNotEmpty && !controller.isClosed) controller.add(left);
      if (_error != null && !controller.isClosed) controller.addError(_error!);
      if (_done && !controller.isClosed) controller.close();
    });
    return controller.stream;
  }

  Future<void> close() => _sub.cancel();
}
