/// Tiny JSON persistence helper with atomic writes (temp file + rename), so a
/// crash can never corrupt sessions/settings.
library;

import 'dart:convert';
import 'dart:io';

class JsonStore {
  JsonStore(this.filePath);

  final String filePath;

  File get _file => File(filePath);

  Future<Map<String, dynamic>?> read() async {
    try {
      final text = await _file.readAsString();
      if (text.trim().isEmpty) return null;
      return jsonDecode(text) as Map<String, dynamic>;
    } on FileSystemException {
      return null;
    } on FormatException {
      // Corrupted file - keep a backup copy for manual inspection.
      try {
        await _file.rename('$filePath.corrupt-${DateTime.now().millisecondsSinceEpoch}');
      } catch (_) {}
      return null;
    }
  }

  Future<void> write(Map<String, dynamic> data) async {
    final f = _file;
    await f.parent.create(recursive: true);
    final tmp = File('$filePath.tmp');
    await tmp.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
    await tmp.rename(filePath);
  }
}
