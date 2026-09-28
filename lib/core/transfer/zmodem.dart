/// ZMODEM (lrzsz) send/receive for the interactive shell.
///
/// Covers the exchange MobaXterm users expect: `sz file` downloads into the
/// local download directory, `rz` uploads a picked file. Frames use the hex
/// header for control messages and CRC-32 binary subpackets for file bytes,
/// which is what current lrzsz negotiates when the receiver advertises
/// CANFC32.
library;

import 'dart:typed_data';

const int zrqinit = 0;
const int zrinit = 1;
const int zfile = 4;
const int zskip = 5;
const int znak = 6;
const int zabort = 7;
const int zfin = 8;
const int zrpos = 9;
const int zdata = 10;
const int zeof = 11;

const int zcrce = 0x68;
const int zcrcg = 0x69;
const int zcrcw = 0x6b;

const int _zdle = 0x18;
const int _canfdx = 0x01;
const int _canovio = 0x02;
const int _canbrk = 0x10;
const int _canfc32 = 0x20;
const int _zrinitFlags = _canfdx | _canovio | _canbrk | _canfc32;

final List<int> _crc32Table = _buildCrc32();

List<int> _buildCrc32() {
  final table = List<int>.filled(256, 0);
  for (var n = 0; n < 256; n++) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1);
    }
    table[n] = c;
  }
  return table;
}

int crc16(List<int> data) {
  var crc = 0;
  for (final b in data) {
    crc ^= (b & 0xff) << 8;
    for (var i = 0; i < 8; i++) {
      if ((crc & 0x8000) != 0) {
        crc = ((crc << 1) ^ 0x1021) & 0xffff;
      } else {
        crc = (crc << 1) & 0xffff;
      }
    }
  }
  return crc;
}

int _crc32Feed(int crc, int byte) =>
    _crc32Table[(crc ^ byte) & 0xff] ^ (crc >> 8);

int crc32(List<int> data) {
  var crc = 0xffffffff;
  for (final b in data) {
    crc = _crc32Feed(crc, b);
  }
  return (~crc) & 0xffffffff;
}

class ZmodemCodec {
  static Uint8List hexHeader(int type, int pos) {
    final body = <int>[
      type & 0xff,
      pos & 0xff,
      (pos >> 8) & 0xff,
      (pos >> 16) & 0xff,
      (pos >> 24) & 0xff,
    ];
    final crc = crc16(body);
    final raw = [...body, (crc >> 8) & 0xff, crc & 0xff];
    final hex = raw.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return Uint8List.fromList([
      0x2a, 0x2a, _zdle, 0x42, // ** <CAN> B
      ...hex.codeUnits,
      0x0d, 0x0a,
    ]);
  }

  static Uint8List bin32Header(int type, int pos) {
    final body = <int>[
      type & 0xff,
      pos & 0xff,
      (pos >> 8) & 0xff,
      (pos >> 16) & 0xff,
      (pos >> 24) & 0xff,
    ];
    final crc = crc32(body);
    final raw = [...body, ..._le32(crc)];
    final out = <int>[0x2a, _zdle, 0x43];
    for (final b in raw) {
      out.addAll(_escape(b));
    }
    return Uint8List.fromList(out);
  }

  static Uint8List subpacket(List<int> data, int frameEnd) {
    final crc = crc32([...data, frameEnd]);
    final out = <int>[];
    for (final b in data) {
      out.addAll(_escape(b));
    }
    out
      ..add(_zdle)
      ..add(frameEnd);
    for (final b in _le32(crc)) {
      out.addAll(_escape(b));
    }
    return Uint8List.fromList(out);
  }

  static List<int> _le32(int v) => [
        v & 0xff,
        (v >> 8) & 0xff,
        (v >> 16) & 0xff,
        (v >> 24) & 0xff,
      ];

  static List<int> _escape(int b) {
    final c = b & 0xff;
    final low = c & 0x7f;
    const special = {0x10, 0x11, 0x13, _zdle, 0x7f};
    if (special.contains(low) || c == _zdle) {
      return [_zdle, c ^ 0x40];
    }
    return [c];
  }

  static String safeName(String name) {
    final base = name.split(RegExp(r'[\\/]')).last.trim();
    if (base.isEmpty || base == '.' || base == '..') return 'download.bin';
    final cleaned = base.replaceAll(RegExp(r'[^A-Za-z0-9._\-]+'), '_');
    return cleaned.isEmpty ? 'download.bin' : cleaned;
  }
}

enum _Phase { idle, session, subpacket }

enum _Role { none, rx, tx }

enum _SubKind { meta, data }

class ZmodemUpload {
  ZmodemUpload({required this.name, required this.bytes});
  final String name;
  final Uint8List bytes;
}

class _Header {
  _Header(this.type, this.pos, this.next);
  final int type;
  final int pos;
  final int next;
}

class _Sub {
  _Sub(this.data, this.frame, this.next, this.ok);
  final List<int> data;
  final int frame;
  final int next;
  final bool ok;
}

/// Incremental ZMODEM state machine. [add] returns bytes that are ordinary
/// terminal output; protocol bytes are consumed.
class ZmodemEngine {
  ZmodemEngine({
    required this.onFile,
    required this.onPick,
    this.onStatus,
  });

  final Future<void> Function(String name, Uint8List bytes) onFile;
  final Future<ZmodemUpload?> Function() onPick;
  final void Function(String message)? onStatus;

  final _buf = <int>[];
  _Phase _phase = _Phase.idle;
  _Role _role = _Role.none;
  _SubKind _subKind = _SubKind.data;
  final _file = BytesBuilder(copy: false);
  String _name = 'download.bin';
  ZmodemUpload? _upload;
  bool _busy = false;
  bool get active => _phase != _Phase.idle || _role != _Role.none;

  Future<Uint8List> add(List<int> data, void Function(Uint8List) write) async {
    _buf.addAll(data);
    final display = <int>[];
    await _drain(display, write);
    return Uint8List.fromList(display);
  }

  Future<void> _drain(List<int> display, void Function(Uint8List) write) async {
    if (_busy) return;
    _busy = true;
    try {
      var guard = 0;
      while (guard++ < 10000) {
        if (_phase == _Phase.subpacket) {
          final sub = _pullSub(0);
          if (sub == null) return;
          _buf.removeRange(0, sub.next);
          if (!sub.ok) {
            onStatus?.call('ZMODEM 校验失败，已请求重发');
            write(ZmodemCodec.hexHeader(znak, 0));
            _phase = _Phase.session;
            continue;
          }
          if (_subKind == _SubKind.meta) {
            _name = _nameOf(sub.data);
            _file.clear();
            write(ZmodemCodec.hexHeader(zrpos, 0));
            onStatus?.call('正在接收 $_name');
          } else {
            _file.add(sub.data);
            if (sub.frame == zcrcw) {
              write(ZmodemCodec.hexHeader(3, _file.length));
            }
          }
          _phase = _Phase.session;
          continue;
        }

        final header = _pullHeader(display, passThrough: _phase == _Phase.idle);
        if (header == null) return;
        _buf.removeRange(0, header.next);
        await _onHeader(header, write);
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> _onHeader(_Header header, void Function(Uint8List) write) async {
    switch (header.type) {
      case zrqinit:
        _role = _Role.rx;
        _phase = _Phase.session;
        write(ZmodemCodec.hexHeader(zrinit, _zrinitFlags));
      case zrinit:
        if (_role == _Role.none) {
          _role = _Role.tx;
          _phase = _Phase.session;
          final file = await onPick();
          if (file == null) {
            write(ZmodemCodec.hexHeader(zfin, 0));
            _finish();
            onStatus?.call('已取消上传');
            return;
          }
          _upload = file;
          write(ZmodemCodec.hexHeader(zfile, 0));
          write(ZmodemCodec.subpacket(_meta(file), zcrcw));
          onStatus?.call('正在发送 ${file.name}');
        }
      case zfile:
        _role = _Role.rx;
        _phase = _Phase.subpacket;
        _subKind = _SubKind.meta;
      case zdata:
        _phase = _Phase.subpacket;
        _subKind = _SubKind.data;
      case zeof:
        final bytes = _file.toBytes();
        await onFile(_name, bytes);
        write(ZmodemCodec.hexHeader(zrpos, bytes.length));
        _file.clear();
        onStatus?.call('已接收 $_name (${bytes.length} 字节)');
        _phase = _Phase.session;
      case zrpos:
        final file = _upload;
        if (file == null || _role != _Role.tx) return;
        final offset = header.pos.clamp(0, file.bytes.length);
        write(ZmodemCodec.bin32Header(zdata, offset));
        final chunk = file.bytes.sublist(offset);
        const size = 1024;
        var at = 0;
        while (at < chunk.length) {
          final end = (at + size < chunk.length) ? at + size : chunk.length;
          final last = end == chunk.length;
          write(ZmodemCodec.subpacket(
            chunk.sublist(at, end),
            last ? zcrce : zcrcg,
          ));
          at = end;
        }
        if (chunk.isEmpty) {
          write(ZmodemCodec.subpacket(const [], zcrce));
        }
        write(ZmodemCodec.bin32Header(zeof, file.bytes.length));
      case zfin:
        if (_role == _Role.tx) {
          write(Uint8List.fromList([0x4f, 0x4f]));
        } else {
          write(ZmodemCodec.hexHeader(zfin, 0));
          write(Uint8List.fromList([0x4f, 0x4f]));
        }
        _finish();
        onStatus?.call('ZMODEM 结束');
      case zabort:
      case zskip:
        _finish();
        onStatus?.call('ZMODEM 已中止');
      default:
        _phase = _Phase.session;
    }
  }

  void _finish() {
    _phase = _Phase.idle;
    _role = _Role.none;
    _upload = null;
    _file.clear();
  }

  List<int> _meta(ZmodemUpload file) => [
        ...file.name.codeUnits,
        0,
        ...'${file.bytes.length} 0 100644'.codeUnits,
        0,
      ];

  String _nameOf(List<int> data) {
    final zero = data.indexOf(0);
    final raw = zero < 0 ? data : data.sublist(0, zero);
    return ZmodemCodec.safeName(String.fromCharCodes(raw));
  }

  _Header? _pullHeader(List<int> display, {required bool passThrough}) {
    if (_buf.length >= 5 &&
        _buf[0] == _zdle &&
        _buf[1] == _zdle &&
        _buf[2] == _zdle &&
        _buf[3] == _zdle &&
        _buf[4] == _zdle) {
      _finish();
      onStatus?.call('ZMODEM 被对端取消');
      return null;
    }
    final at = _findHeader(0);
    if (at < 0) {
      final keep = _prefixLength();
      if (passThrough) {
        final n = _buf.length - keep;
        if (n > 0) {
          display.addAll(_buf.sublist(0, n));
          _buf.removeRange(0, n);
        }
      } else if (_buf.length > 64 && keep == 0) {
        _finish();
      }
      return null;
    }
    if (passThrough && at > 0) {
      display.addAll(_buf.sublist(0, at));
    }
    final marker = _markerLen(at);
    if (marker == null) return null;
    if (_buf[at + marker - 1] == 0x42) {
      return _parseHex(at, marker);
    }
    return _parseBin32(at, marker);
  }

  int _findHeader(int from) {
    for (var i = from; i < _buf.length - 2; i++) {
      if (_buf[i] != 0x2a) continue;
      if (i + 3 < _buf.length &&
          _buf[i + 1] == 0x2a &&
          _buf[i + 2] == _zdle &&
          _isType(_buf[i + 3])) {
        return i;
      }
      if (i + 2 < _buf.length && _buf[i + 1] == _zdle && _isType(_buf[i + 2])) {
        return i;
      }
    }
    return -1;
  }

  bool _isType(int b) => b == 0x41 || b == 0x42 || b == 0x43;

  int? _markerLen(int at) {
    if (at + 3 < _buf.length && _buf[at + 1] == 0x2a) return 4;
    if (at + 2 < _buf.length && _buf[at + 1] == _zdle) return 3;
    return null;
  }

  int _prefixLength() {
    if (_buf.isEmpty) return 0;
    final tail = _buf.sublist(_buf.length > 3 ? _buf.length - 3 : 0);
    const prefixes = [
      [0x2a, 0x2a, _zdle],
      [0x2a, 0x2a],
      [0x2a, _zdle],
      [0x2a],
    ];
    for (final p in prefixes) {
      if (tail.length >= p.length &&
          _endsWith(tail, p)) {
        return p.length;
      }
    }
    return 0;
  }

  bool _endsWith(List<int> data, List<int> suffix) {
    if (data.length < suffix.length) return false;
    for (var i = 0; i < suffix.length; i++) {
      if (data[data.length - suffix.length + i] != suffix[i]) return false;
    }
    return true;
  }

  _Header? _parseHex(int at, int marker) {
    final start = at + marker;
    if (_buf.length < start + 14) return null;
    if (_buf.length == start + 14) return null;
    final hex = String.fromCharCodes(_buf.sublist(start, start + 14));
    if (!RegExp(r'^[0-9a-fA-F]+$').hasMatch(hex)) {
      _buf.removeAt(at);
      return null;
    }
    final bytes = <int>[];
    for (var i = 0; i < 14; i += 2) {
      bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    final crc = crc16(bytes.sublist(0, 5));
    final got = (bytes[5] << 8) | bytes[6];
    if (crc != got) {
      _buf.removeAt(at);
      return null;
    }
    var end = start + 14;
    if (end < _buf.length && _buf[end] == 0x0d) end++;
    if (end < _buf.length && (_buf[end] == 0x0a || _buf[end] == 0x8a)) end++;
    if (end < _buf.length && _buf[end] == 0x11) end++;
    final pos = bytes[1] | (bytes[2] << 8) | (bytes[3] << 16) | (bytes[4] << 24);
    return _Header(bytes[0], pos, end);
  }

  _Header? _parseBin32(int at, int marker) {
    final got = _readEscapedBytes(at + marker, 9);
    if (got == null) return null;
    final bytes = got.$1;
    final crc = crc32(bytes.sublist(0, 5));
    final wire = bytes[5] |
        (bytes[6] << 8) |
        (bytes[7] << 16) |
        (bytes[8] << 24);
    if (crc != wire) {
      _buf.removeAt(at);
      return null;
    }
    final pos = bytes[1] | (bytes[2] << 8) | (bytes[3] << 16) | (bytes[4] << 24);
    return _Header(bytes[0], pos, got.$2);
  }

  _Sub? _pullSub(int from) {
    final data = <int>[];
    var crc = 0xffffffff;
    var i = from;
    while (true) {
      final one = _readOne(i);
      if (one == null) return null;
      i = one.next;
      if (one.frameEnd != null) {
        crc = _crc32Feed(crc, one.frameEnd!);
        final crcBytes = _readEscapedBytes(i, 4);
        if (crcBytes == null) return null;
        for (final b in crcBytes.$1) {
          crc = _crc32Feed(crc, b);
        }
        final ok = (crc & 0xffffffff) == 0xdebb20e3;
        return _Sub(data, one.frameEnd!, crcBytes.$2, ok);
      }
      data.add(one.byte!);
      crc = _crc32Feed(crc, one.byte!);
    }
  }

  (List<int>, int)? _readEscapedBytes(int i, int n) {
    final out = <int>[];
    var at = i;
    for (var k = 0; k < n; k++) {
      final one = _readOne(at);
      if (one == null || one.frameEnd != null || one.byte == null) return null;
      out.add(one.byte!);
      at = one.next;
    }
    return (out, at);
  }

  _One? _readOne(int i) {
    if (i >= _buf.length) return null;
    final c = _buf[i];
    if (c != _zdle) return _One(byte: c, next: i + 1);
    if (i + 1 >= _buf.length) return null;
    final n = _buf[i + 1];
    if (n == zcrce || n == zcrcg || n == 0x6a || n == zcrcw) {
      return _One(frameEnd: n, next: i + 2);
    }
    return _One(byte: n ^ 0x40, next: i + 2);
  }
}

class _One {
  _One({this.byte, this.frameEnd, required this.next});
  final int? byte;
  final int? frameEnd;
  final int next;
}
