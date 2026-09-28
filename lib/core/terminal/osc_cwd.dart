/// Pulls OSC 7 (current working directory) out of a terminal byte stream
/// without hiding any other sequence. Supports both BEL and ST terminators,
/// and the `file://host/path` form used by bash/zsh.
library;

import 'dart:convert';
import 'dart:typed_data';

class OscCwdExtractor {
  final _decoder = const Utf8Decoder(allowMalformed: true);
  String _carry = '';

  /// Returns text that should be shown, and the latest directory if one was
  /// reported in this chunk.
  ({String text, String? cwd}) push(List<int> bytes) {
    final chunk = _carry + _decoder.convert(bytes);
    _carry = '';
    final out = StringBuffer();
    String? cwd;
    var i = 0;
    while (i < chunk.length) {
      final esc = chunk.indexOf('\x1b', i);
      if (esc < 0) {
        out.write(chunk.substring(i));
        break;
      }
      out.write(chunk.substring(i, esc));
      if (esc + 1 >= chunk.length) {
        _carry = chunk.substring(esc);
        break;
      }
      if (chunk[esc + 1] != ']') {
        out.write(chunk[esc]);
        i = esc + 1;
        continue;
      }
      final bel = chunk.indexOf('\x07', esc + 2);
      final st = chunk.indexOf('\x1b\\', esc + 2);
      var end = -1;
      var payloadEnd = -1;
      if (bel >= 0 && (st < 0 || bel < st)) {
        end = bel + 1;
        payloadEnd = bel;
      } else if (st >= 0) {
        end = st + 2;
        payloadEnd = st;
      }
      if (end < 0) {
        _carry = chunk.substring(esc);
        if (_carry.length > 2048) {
          out.write(_carry[0]);
          _carry = _carry.substring(1);
        }
        break;
      }
      final payload = chunk.substring(esc + 2, payloadEnd);
      final parsed = parseOsc7(payload);
      if (parsed != null) {
        cwd = parsed;
      } else {
        out.write(chunk.substring(esc, end));
      }
      i = end;
    }
    return (text: out.toString(), cwd: cwd);
  }

  void reset() => _carry = '';
}

/// Returns a filesystem path when [payload] is an OSC 7 body (`7;...`).
String? parseOsc7(String payload) {
  if (!payload.startsWith('7;')) return null;
  var value = payload.substring(2).trim();
  if (value.isEmpty) return null;
  if (value.startsWith('file://')) {
    final rest = value.substring('file://'.length);
    final slash = rest.indexOf('/');
    if (slash < 0) return null;
    value = rest.substring(slash);
    try {
      value = Uri.decodeComponent(value);
    } catch (_) {}
  }
  if (!value.startsWith('/')) return null;
  return value;
}

/// Bytes of a shell hook that reports `$PWD` before each prompt.
///
/// The backslashes are intentional: the remote shell's `printf` interprets
/// `\033`, and `$PWD` is expanded when `PROMPT_COMMAND` runs.
Uint8List cwdTrackingCommand() {
  const cmd =
      'if [ -n "\$BASH_VERSION" ]; then PROMPT_COMMAND=\'printf "\\033]7;%s\\007" "\$PWD"\'; elif [ -n "\$ZSH_VERSION" ]; then precmd() { printf "\\033]7;%s\\007" "\$PWD"; }; fi\n';
  return Uint8List.fromList(utf8.encode(cmd));
}
