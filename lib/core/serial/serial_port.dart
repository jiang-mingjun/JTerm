/// Linux serial ports via libc termios. No extra plugin: the fd is process-wide,
/// so a helper isolate can block in `read` without freezing the UI.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

const int _oRdwr = 2;
const int _oNoctty = 256;
const int _oNonblock = 2048;
const int _fGetfl = 3;
const int _fSetfl = 4;
const int _tcsanow = 0;
const int _vmin = 6;
const int _vtime = 5;
const int _cs7 = 32;
const int _cs8 = 48;
const int _cstopb = 64;
const int _cread = 128;
const int _parenb = 256;
const int _parodd = 512;
const int _clocal = 2048;

const Map<int, int> _baud = {
  9600: 13,
  19200: 14,
  38400: 15,
  57600: 4097,
  115200: 4098,
  230400: 4099,
};

class SerialPortException implements Exception {
  SerialPortException(this.message);
  final String message;
  @override
  String toString() => message;
}

class SerialPort {
  SerialPort._(this._fd, this._libc, this._reader);

  final int _fd;
  final DynamicLibrary _libc;
  final Isolate _reader;
  Stream<Uint8List> get stream => _stream.stream;
  final _stream = StreamController<Uint8List>();
  ReceivePort? _receive;
  bool _open = true;

  static List<String> listDevices() {
    final dev = Directory('/dev');
    if (!dev.existsSync()) return const [];
    final names = dev
        .listSync()
        .map((e) => e.path)
        .where((p) {
          final n = p.split('/').last;
          return n.startsWith('ttyUSB') ||
              n.startsWith('ttyACM') ||
              n.startsWith('ttyAMA') ||
              n.startsWith('ttyS');
        })
        .toList();
    names.sort();
    return names;
  }

  static Future<SerialPort> open(
    String path, {
    int baudRate = 115200,
    int dataBits = 8,
    String parity = 'none',
    int stopBits = 1,
  }) async {
    if (!Platform.isLinux) {
      throw SerialPortException('串口目前仅支持 Linux');
    }
    final libc = DynamicLibrary.open('libc.so.6');
    final openFn = libc.lookupFunction<
        Int32 Function(Pointer<Char>, Int32),
        int Function(Pointer<Char>, int)>('open');
    final cPath = _cString(libc, path);
    final fd = openFn(cPath.cast<Char>(), _oRdwr | _oNoctty | _oNonblock);
    _free(libc, cPath);
    if (fd < 0) {
      throw SerialPortException('无法打开 $path');
    }
    try {
      _configure(libc, fd,
          baudRate: baudRate, dataBits: dataBits, parity: parity, stopBits: stopBits);
      final fcntl = libc.lookupFunction<
          Int32 Function(Int32, Int32, Int32),
          int Function(int, int, int)>('fcntl');
      final flags = fcntl(fd, _fGetfl, 0);
      fcntl(fd, _fSetfl, flags & ~_oNonblock);
    } catch (e) {
      libc.lookupFunction<Int32 Function(Int32), int Function(int)>('close')(fd);
      throw SerialPortException(e.toString());
    }

    final receive = ReceivePort();
    final isolate = await Isolate.spawn(_readLoop, [fd, receive.sendPort]);
    final port = SerialPort._(fd, libc, isolate);
    port._receive = receive;
    receive.listen((message) {
      if (message == null) {
        if (!port._stream.isClosed) port._stream.close();
        return;
      }
      if (message is Uint8List && !port._stream.isClosed) {
        port._stream.add(message);
      }
    });
    return port;
  }

  static void _configure(
    DynamicLibrary libc,
    int fd, {
    required int baudRate,
    required int dataBits,
    required String parity,
    required int stopBits,
  }) {
    final speed = _baud[baudRate];
    if (speed == null) {
      throw SerialPortException('不支持的波特率 $baudRate');
    }
    final termios = _malloc(libc, 60);
    try {
      final getattr = libc.lookupFunction<
          Int32 Function(Int32, Pointer<Uint8>),
          int Function(int, Pointer<Uint8>)>('tcgetattr');
      final setattr = libc.lookupFunction<
          Int32 Function(Int32, Int32, Pointer<Uint8>),
          int Function(int, int, Pointer<Uint8>)>('tcsetattr');
      final setIn = libc.lookupFunction<
          Int32 Function(Pointer<Uint8>, Uint32),
          int Function(Pointer<Uint8>, int)>('cfsetispeed');
      final setOut = libc.lookupFunction<
          Int32 Function(Pointer<Uint8>, Uint32),
          int Function(Pointer<Uint8>, int)>('cfsetospeed');
      if (getattr(fd, termios) != 0) {
        throw SerialPortException('读取串口参数失败');
      }
      final data = termios.asTypedList(60);
      _setU32(data, 0, 0);
      _setU32(data, 4, 0);
      var cflag = _cread | _clocal | (dataBits == 7 ? _cs7 : _cs8);
      if (parity == 'even') cflag |= _parenb;
      if (parity == 'odd') cflag |= _parenb | _parodd;
      if (stopBits == 2) cflag |= _cstopb;
      _setU32(data, 8, cflag);
      _setU32(data, 12, 0);
      data[17 + _vtime] = 0;
      data[17 + _vmin] = 1;
      if (setIn(termios, speed) != 0 || setOut(termios, speed) != 0) {
        throw SerialPortException('设置波特率失败');
      }
      if (setattr(fd, _tcsanow, termios) != 0) {
        throw SerialPortException('应用串口参数失败');
      }
    } finally {
      _free(libc, termios);
    }
  }

  void write(List<int> bytes) {
    if (!_open || bytes.isEmpty) return;
    final writeFn = _libc.lookupFunction<
        IntPtr Function(Int32, Pointer<Uint8>, IntPtr),
        int Function(int, Pointer<Uint8>, int)>('write');
    final buf = _malloc(_libc, bytes.length);
    try {
      buf.asTypedList(bytes.length).setAll(0, bytes);
      writeFn(_fd, buf, bytes.length);
    } finally {
      _free(_libc, buf);
    }
  }

  Future<void> close() async {
    if (!_open) return;
    _open = false;
    _reader.kill(priority: Isolate.immediate);
    _receive?.close();
    _libc.lookupFunction<Int32 Function(Int32), int Function(int)>('close')(_fd);
    if (!_stream.isClosed) await _stream.close();
  }
}

void _setU32(List<int> data, int offset, int value) {
  data[offset] = value & 0xff;
  data[offset + 1] = (value >> 8) & 0xff;
  data[offset + 2] = (value >> 16) & 0xff;
  data[offset + 3] = (value >> 24) & 0xff;
}

void _readLoop(List<Object> args) {
  final fd = args[0] as int;
  final send = args[1] as SendPort;
  final libc = DynamicLibrary.open('libc.so.6');
  final readFn = libc.lookupFunction<
      IntPtr Function(Int32, Pointer<Uint8>, IntPtr),
      int Function(int, Pointer<Uint8>, int)>('read');
  final buf = _malloc(libc, 4096);
  try {
    while (true) {
      final n = readFn(fd, buf, 4096);
      if (n <= 0) {
        send.send(null);
        break;
      }
      send.send(Uint8List.fromList(buf.asTypedList(n)));
    }
  } finally {
    _free(libc, buf);
  }
}

Pointer<Uint8> _malloc(DynamicLibrary libc, int size) {
  final malloc = libc.lookupFunction<Pointer<Uint8> Function(IntPtr),
      Pointer<Uint8> Function(int)>('malloc');
  final p = malloc(size);
  if (p == nullptr) {
    throw SerialPortException('内存分配失败');
  }
  return p;
}

void _free(DynamicLibrary libc, Pointer<Uint8> p) {
  libc.lookupFunction<Void Function(Pointer<Uint8>), void Function(Pointer<Uint8>)>(
      'free')(p);
}

Pointer<Uint8> _cString(DynamicLibrary libc, String text) {
  final bytes = utf8.encode('$text\x00');
  final p = _malloc(libc, bytes.length);
  p.asTypedList(bytes.length).setAll(0, bytes);
  return p;
}
