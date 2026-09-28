/// OSC 7 (`ESC ] 7 ; file://host/path BEL`) carries the shell's working
/// directory. Bash/zsh emit it when `PROMPT_COMMAND` / `chpwd` is configured,
/// which is how modern terminals track the remote folder.
library;

String? pathFromOsc7(String payload) {
  var value = payload.trim();
  if (value.isEmpty) return null;
  if (value.startsWith('file://')) {
    value = value.substring('file://'.length);
    final slash = value.indexOf('/');
    if (slash < 0) return null;
    value = value.substring(slash);
  }
  if (!value.startsWith('/')) return null;
  final cut = value.split('\x1b').first.split('\x07').first;
  try {
    return Uri.decodeFull(cut);
  } catch (_) {
    return cut;
  }
}

Iterable<String> osc7Payloads(String chunk) sync* {
  final matches = RegExp(r'\x1b\]7;([^\x07\x1b]+)').allMatches(chunk);
  for (final match in matches) {
    final payload = match.group(1);
    if (payload != null && payload.isNotEmpty) yield payload;
  }
}
