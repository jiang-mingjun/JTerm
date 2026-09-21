import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:xterm/xterm.dart';

import '../../core/terminal/terminal_session.dart';
import '../../state/settings_state.dart';
import '../../state/tabs_state.dart';

/// One terminal tab page: the xterm view plus a thin connection overlay.
class TerminalPage extends StatefulWidget {
  const TerminalPage({super.key, required this.tab, required this.tabs});

  final TabEntry tab;
  final TabsState tabs;

  @override
  State<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends State<TerminalPage> {
  final _controller = TerminalController();

  TerminalSessionBase get session => widget.tab.session;

  @override
  void initState() {
    super.initState();
    // TerminalView auto-resizes the terminal core; forward that to the PTY.
    session.terminal.onResize = (cols, rows, pw, ph) {
      // ignore: discarded_futures
      session.resize(cols, rows);
    };
    if (session.status == SessionStatus.disconnected) {
      // e.g. after a tab-strip "reconnect"
      // ignore: discarded_futures
      session.connect();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsState>();
    final scheme = Theme.of(context).colorScheme;

    return Stack(
      children: [
        TerminalView(
          session.terminal,
          controller: _controller,
          autofocus: true,
          padding: const EdgeInsets.all(6),
          textStyle: TerminalStyle(
            fontSize: settings.fontSize,
            fontFamily: settings.fontFamily.isEmpty
                ? 'monospace'
                : settings.fontFamily,
          ),
          onSecondaryTapUp: (details, _) {
            _contextMenu(context, details.globalPosition);
          },
          backgroundOpacity: 1,
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
                          Text(switch (session.status) {
                            SessionStatus.connecting => '正在连接…',
                            SessionStatus.reconnecting => '正在重连…',
                            SessionStatus.failed =>
                              '连接失败: ${session.failMessage}',
                            _ => '',
                          }),
                          if (session.status == SessionStatus.failed ||
                              session.status ==
                                  SessionStatus.disconnected) ...[
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

  void _contextMenu(BuildContext context, Offset pos) {
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx + 1, pos.dy + 1),
      items: [
        const PopupMenuItem(value: 'copy', child: Text('复制选中内容')),
        const PopupMenuItem(value: 'paste', child: Text('粘贴')),
        const PopupMenuItem(value: 'clear', child: Text('清屏')),
      ],
    ).then((v) async {
      final sel = _controller.selection;
      switch (v) {
        case 'copy':
          if (sel != null) {
            final text = session.terminal.buffer.getText(sel);
            if (text.isNotEmpty) {
              // ignore: avoid_print
              await Clipboard.setData(ClipboardData(text: text));
            }
          }
        case 'paste':
          final data = await Clipboard.getData('text/plain');
          if (data?.text != null) {
            session.terminal.onOutput?.call(data!.text!);
          }
        case 'clear':
          session.terminal.eraseDisplay();
          session.terminal.buffer.setCursor(0, 0);
      }
    });
  }
}
