import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:xterm/xterm.dart';

import '../../core/terminal/terminal_session.dart';
import '../../core/terminal/terminal_themes.dart';
import '../../state/settings_state.dart';
import '../../state/tabs_state.dart';

/// One terminal tab page: the xterm view, search, and a connection overlay.
class TerminalPage extends StatefulWidget {
  const TerminalPage({super.key, required this.tab, required this.tabs});

  final TabEntry tab;
  final TabsState tabs;

  @override
  State<TerminalPage> createState() => _TerminalPageState();
}

class _Hit {
  _Hit(this.line, this.start, this.end);
  final int line;
  final int start;
  final int end;
}

class _TerminalPageState extends State<TerminalPage> {
  final _controller = TerminalController();
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  bool _searchOpen = false;
  bool _bell = false;
  final List<_Hit> _hits = [];
  int _hitIndex = 0;
  Timer? _copyTimer;
  Timer? _bellTimer;

  TerminalSessionBase get session => widget.tab.session;

  @override
  void initState() {
    super.initState();
    session.terminal.onResize = (cols, rows, pw, ph) {
      session.resize(cols, rows);
    };
    session.terminal.onBell = () {
      final settings = context.read<SettingsState>();
      if (!settings.visualBell || !mounted) return;
      setState(() => _bell = true);
      _bellTimer?.cancel();
      _bellTimer = Timer(const Duration(milliseconds: 900), () {
        if (mounted) setState(() => _bell = false);
      });
    };
    _controller.addListener(_onSelection);
    if (session.status == SessionStatus.disconnected) {
      // ignore: discarded_futures
      session.connect();
    }
  }

  @override
  void dispose() {
    _copyTimer?.cancel();
    _bellTimer?.cancel();
    _controller.removeListener(_onSelection);
    _controller.dispose();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onSelection() {
    if (!mounted) return;
    final settings = context.read<SettingsState>();
    if (!settings.copyOnSelect) return;
    _copyTimer?.cancel();
    _copyTimer = Timer(const Duration(milliseconds: 280), () async {
      final selection = _controller.selection;
      if (selection == null) return;
      final text = session.terminal.buffer.getText(selection);
      if (text.isEmpty) return;
      await Clipboard.setData(ClipboardData(text: text));
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsState>();
    final scheme = Theme.of(context).colorScheme;
    final cursor = switch (settings.cursorStyle) {
      'underline' => TerminalCursorType.underline,
      'bar' => TerminalCursorType.verticalBar,
      _ => TerminalCursorType.block,
    };

    return Stack(
      children: [
        Column(
          children: [
            if (_searchOpen) _searchBar(scheme),
            Expanded(
              child: TerminalView(
                session.terminal,
                controller: _controller,
                autofocus: true,
                padding: const EdgeInsets.all(6),
                theme: terminalThemeById(settings.terminalTheme),
                cursorType: cursor,
                textStyle: TerminalStyle(
                  fontSize: settings.fontSize,
                  fontFamily: settings.fontFamily.isEmpty
                      ? 'monospace'
                      : settings.fontFamily,
                ),
                onKeyEvent: _onKey,
                onTapUp: (details, offset) => _openLink(offset),
                onSecondaryTapUp: (details, _) {
                  _contextMenu(context, details.globalPosition);
                },
                backgroundOpacity: 1,
              ),
            ),
          ],
        ),
        if (_bell)
          Positioned(
            top: 8,
            right: 8,
            child: Material(
              color: scheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(6),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text('铃', style: TextStyle(fontSize: 11)),
              ),
            ),
          ),
        StreamBuilder<SessionEvent>(
          stream: session.events,
          builder: (context, snap) {
            if (session.status == SessionStatus.connected ||
                session.status == SessionStatus.disconnected) {
              return const SizedBox.shrink();
            }
            return Positioned.fill(
              child: ColoredBox(
                color: scheme.scrim.withValues(alpha: 0.55),
                child: Center(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          session.status == SessionStatus.failed
                              ? Icon(Icons.error_outline,
                                  color: scheme.error, size: 36)
                              : const SizedBox(
                                  width: 32,
                                  height: 32,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 3)),
                          const SizedBox(height: 12),
                          Text(
                            switch (session.status) {
                              SessionStatus.connecting => '正在连接…',
                              SessionStatus.reconnecting =>
                                '正在重连… ${session.failMessage}',
                              SessionStatus.failed =>
                                '连接失败: ${session.failMessage}',
                              _ => '',
                            },
                            textAlign: TextAlign.center,
                          ),
                          if (session.status == SessionStatus.failed) ...[
                            const SizedBox(height: 12),
                            FilledButton.tonal(
                              onPressed: () => session.connect(),
                              child: const Text('重试'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _searchBar(ColorScheme scheme) {
    final label = _hits.isEmpty
        ? (_searchCtrl.text.isEmpty ? '' : '无匹配')
        : '${_hitIndex + 1}/${_hits.length}';
    return Material(
      color: scheme.surfaceContainerHigh,
      child: SizedBox(
        height: 36,
        child: Row(
          children: [
            const SizedBox(width: 8),
            const Icon(Icons.search, size: 16),
            const SizedBox(width: 6),
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                focusNode: _searchFocus,
                style: const TextStyle(fontSize: 13),
                decoration: const InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: '在回滚缓冲区中查找',
                ),
                onChanged: _runSearch,
                onSubmitted: (_) => _step(1),
              ),
            ),
            Text(label, style: TextStyle(fontSize: 11, color: scheme.outline)),
            IconButton(
              tooltip: '上一个',
              icon: const Icon(Icons.keyboard_arrow_up, size: 18),
              onPressed: () => _step(-1),
            ),
            IconButton(
              tooltip: '下一个',
              icon: const Icon(Icons.keyboard_arrow_down, size: 18),
              onPressed: () => _step(1),
            ),
            IconButton(
              tooltip: '关闭',
              icon: const Icon(Icons.close, size: 16),
              onPressed: _closeSearch,
            ),
          ],
        ),
      ),
    );
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    if (ctrl && event.logicalKey == LogicalKeyboardKey.keyF) {
      _openSearch();
      return KeyEventResult.handled;
    }
    if (ctrl && shift && event.logicalKey == LogicalKeyboardKey.keyC) {
      _copySelection();
      return KeyEventResult.handled;
    }
    if (ctrl && shift && event.logicalKey == LogicalKeyboardKey.keyV) {
      _paste();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape && _searchOpen) {
      _closeSearch();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _openSearch() {
    setState(() => _searchOpen = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocus.requestFocus();
    });
  }

  void _closeSearch() {
    _controller.clearSelection();
    setState(() {
      _searchOpen = false;
      _hits.clear();
    });
  }

  void _runSearch(String query) {
    _hits.clear();
    if (query.isEmpty) {
      _controller.clearSelection();
      setState(() {});
      return;
    }
    final needle = query.toLowerCase();
    final lines = session.terminal.buffer.lines;
    for (var i = 0; i < lines.length; i++) {
      final text = lines[i].getText().toLowerCase();
      var from = 0;
      while (from < text.length) {
        final at = text.indexOf(needle, from);
        if (at < 0) break;
        _hits.add(_Hit(i, at, at + needle.length));
        from = at + needle.length;
      }
    }
    _hitIndex = _hits.isEmpty ? 0 : _hits.length - 1;
    _selectHit();
    setState(() {});
  }

  void _step(int delta) {
    if (_hits.isEmpty) return;
    _hitIndex = (_hitIndex + delta) % _hits.length;
    if (_hitIndex < 0) _hitIndex += _hits.length;
    _selectHit();
    setState(() {});
  }

  void _selectHit() {
    if (_hits.isEmpty) return;
    final hit = _hits[_hitIndex];
    final lines = session.terminal.buffer.lines;
    if (hit.line < 0 || hit.line >= lines.length) return;
    final end = hit.end <= hit.start ? hit.start : hit.end - 1;
    _controller.setSelection(
      lines[hit.line].createAnchor(hit.start),
      lines[hit.line].createAnchor(end),
    );
  }

  Future<void> _openLink(CellOffset offset) async {
    if (!HardwareKeyboard.instance.isControlPressed) return;
    final lines = session.terminal.buffer.lines;
    if (offset.y < 0 || offset.y >= lines.length) return;
    final text = lines[offset.y].getText();
    final url = _urlAt(text, offset.x);
    if (url == null) return;
    final uri = Uri.tryParse(url);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _contextMenu(BuildContext context, Offset pos) {
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx + 1, pos.dy + 1),
      items: const [
        PopupMenuItem(value: 'copy', child: Text('复制')),
        PopupMenuItem(value: 'paste', child: Text('粘贴')),
        PopupMenuItem(value: 'all', child: Text('全选')),
        PopupMenuItem(value: 'find', child: Text('查找  Ctrl+F')),
        PopupMenuItem(value: 'save', child: Text('保存输出…')),
        PopupMenuItem(value: 'clear', child: Text('清屏')),
      ],
    ).then((value) async {
      switch (value) {
        case 'copy':
          await _copySelection();
        case 'paste':
          await _paste();
        case 'all':
          _selectAll();
        case 'find':
          _openSearch();
        case 'save':
          await _saveOutput();
        case 'clear':
          session.terminal.eraseDisplay();
          session.terminal.buffer.setCursor(0, 0);
      }
    });
  }

  Future<void> _copySelection() async {
    final selection = _controller.selection;
    if (selection == null) return;
    final text = session.terminal.buffer.getText(selection);
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData('text/plain');
    final text = data?.text;
    if (text != null && text.isNotEmpty) {
      session.terminal.paste(text);
    }
  }

  void _selectAll() {
    final lines = session.terminal.buffer.lines;
    if (lines.length == 0) return;
    final last = lines.length - 1;
    final lastText = lines[last].getText();
    _controller.setSelection(
      lines[0].createAnchor(0),
      lines[last].createAnchor(lastText.isEmpty ? 0 : lastText.length - 1),
    );
  }

  Future<void> _saveOutput() async {
    final location = await getSaveLocation(
      suggestedName: '${widget.tab.title}.log',
    );
    if (location == null) return;
    final text = session.terminal.buffer.getText();
    await File(location.path).writeAsString(text);
  }
}

String? _urlAt(String text, int column) {
  final pattern = RegExp(r'https?://[^\s<>"]+');
  for (final match in pattern.allMatches(text)) {
    if (column >= match.start && column < match.end) {
      var url = match.group(0)!;
      while (url.endsWith('.') ||
          url.endsWith(',') ||
          url.endsWith(')') ||
          url.endsWith(';')) {
        url = url.substring(0, url.length - 1);
      }
      return url;
    }
  }
  return null;
}
