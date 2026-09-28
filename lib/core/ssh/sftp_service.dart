/// SFTP service - directory browsing and file transfer on top of a live SSH
/// connection. This powers the MobaXterm-style left sidebar browser.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import 'ssh_connection.dart';

class SftpEntry {
  SftpEntry({
    required this.name,
    required this.fullPath,
    required this.isDirectory,
    required this.isLink,
    required this.size,
    required this.modeValue,
    required this.modifiedMs,
    required this.owner,
    required this.group,
  });

  final String name;
  final String fullPath;
  final bool isDirectory;
  final bool isLink;
  final int size;
  final int modeValue;
  final int modifiedMs;
  final String owner;
  final String group;

  bool get readable => (modeValue & 0x100) != 0;
  bool get writable => (modeValue & 0x80) != 0;
  bool get executable => (modeValue & 0x40) != 0;

  /// `drwxr-xr-x` style representation.
  String get modeString {
    const rwx = 'rwx';
    final buf = StringBuffer();
    if (isLink) {
      buf.write('l');
    } else {
      buf.write(isDirectory ? 'd' : '-');
    }
    for (var shift = 6; shift >= 0; shift -= 3) {
      for (var i = 0; i < 3; i++) {
        buf.write((modeValue >> (shift - i)) & 1 == 1 ? rwx[i] : '-');
      }
    }
    return buf.toString();
  }
}

class SftpService {
  SftpService(this.connection);

  final SshConnection connection;
  SftpClient? _sftp;

  Future<SftpClient> get client async => _sftp ??= await connection.client!.sftp();

  String cwd = '/';

  Future<void> close() async {
    await _sftp?.close();
    _sftp = null;
  }

  Future<List<SftpEntry>> list(String path) async {
    final sftp = await client;
    final real = await sftp.absolute(path);
    cwd = real;
    final names = await sftp.listdir(real);
    final entries = <SftpEntry>[];
    for (final n in names) {
      if (n.filename == '.' ) continue;
      final attrs = n.attr;
      final mode = attrs.mode?.value ?? 0;
      entries.add(SftpEntry(
        name: n.filename,
        fullPath: real == '/' ? '/${n.filename}' : '$real/${n.filename}',
        isDirectory: (mode & 0xF000) == 0x4000 && n.filename != '..',
        isLink: (mode & 0xF000) == 0xA000,
        size: attrs.size ?? 0,
        modeValue: mode & 0xFFF,
        modifiedMs: (attrs.modifyTime ?? 0) * 1000,
        owner: attrs.userID?.toString() ?? '-',
        group: attrs.groupID?.toString() ?? '-',
      ));
    }
    // Folders first (except the parent entry), then alphabetical.
    entries.sort((a, b) {
      if (a.name == '..') return -1;
      if (b.name == '..') return 1;
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return entries;
  }

  Future<void> downloadFile(
    String remotePath,
    File localTarget, {
    void Function(int done, int total)? onProgress,
  }) async {
    final sftp = await client;
    final attrs = await sftp.stat(remotePath);
    final total = attrs.size ?? 0;
    final sink = localTarget.openWrite();
    try {
      await sftp.download(
        remotePath,
        sink,
        onProgress: (read) => onProgress?.call(read, total),
        closeDestination: true,
      );
    } catch (_) {
      await sink.close();
      rethrow;
    }
  }

  Future<void> uploadFile(
    File localSource,
    String remotePath, {
    void Function(int done, int total)? onProgress,
  }) async {
    final sftp = await client;
    final total = await localSource.length();
    final file = await sftp.open(
      remotePath,
      mode: SftpFileOpenMode.write |
          SftpFileOpenMode.create |
          SftpFileOpenMode.truncate,
    );
    final stream = localSource.openRead().map(
          (d) => Uint8List.fromList(d),
        );
    final writer = file.write(
      stream,
      onProgress: (bytes) {
        onProgress?.call(bytes, total);
      },
    );
    try {
      await writer.done;
    } finally {
      await file.close();
    }
  }

  Future<void> rename(String oldPath, String newPath) async =>
      (await client).rename(oldPath, newPath);

  Future<void> deleteFile(String path) async => (await client).remove(path);

  Future<void> deleteDir(String path) async => (await client).rmdir(path);

  Future<void> mkdir(String path) async => (await client).mkdir(path);

  Future<Uint8List> readBytes(String path, {int maxBytes = 1024 * 1024}) async {
    final sftp = await client;
    final file = await sftp.open(path);
    try {
      return await file.readBytes(length: maxBytes);
    } finally {
      await file.close();
    }
  }

  Future<String> readText(String path, {int maxBytes = 1024 * 1024}) async {
    final sftp = await client;
    final size = (await sftp.stat(path)).size ?? 0;
    if (size > maxBytes) {
      throw StateError('文件超过 1MB，请在远程用编辑器打开');
    }
    final bytes = await readBytes(path, maxBytes: maxBytes);
    if (bytes.contains(0)) {
      throw StateError('这不是文本文件');
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  Future<void> writeText(String path, String text) async {
    final sftp = await client;
    final file = await sftp.open(
      path,
      mode: SftpFileOpenMode.write |
          SftpFileOpenMode.create |
          SftpFileOpenMode.truncate,
    );
    try {
      final writer = file.write(
        Stream.value(Uint8List.fromList(utf8.encode(text))),
      );
      await writer.done;
    } finally {
      await file.close();
    }
  }

  Future<void> removeTree(String path) async {
    final entries = await list(path);
    for (final entry in entries) {
      if (entry.name == '.' || entry.name == '..') continue;
      if (entry.isDirectory) {
        await removeTree(entry.fullPath);
      } else {
        await deleteFile(entry.fullPath);
      }
    }
    await deleteDir(path);
  }

  Future<void> chmod(String path, int mode) async {
    final sftp = await client;
    await sftp.setStat(path, SftpFileAttrs(mode: SftpFileMode.value(mode)));
  }

  Future<int> sizeOf(String path) async =>
      (await (await client).stat(path)).size ?? 0;
}
