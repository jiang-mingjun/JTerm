import 'package:flutter/material.dart';

import '../../core/models/session_profile.dart';
import '../../state/app_state.dart';
import '../../state/tabs_state.dart';
import '../dialogs/app_dialogs.dart';
import '../sftp/sftp_panel.dart';
import '../session/session_edit_dialog.dart';
import '../session/macro_panel.dart';

/// Left sidebar with three stacked panes: sessions, SFTP browser, macros.
class SessionSidebar extends StatefulWidget {
  const SessionSidebar({super.key, required this.tabs, required this.app});

  final TabsState tabs;
  final AppState app;

  @override
  State<SessionSidebar> createState() => _SessionSidebarState();
}

class _SessionSidebarState extends State<SessionSidebar> {
  int _pane = 0;

  @override
  Widget build(BuildContext context) {
    final tabs = widget.tabs;
    final app = widget.app;
    final scheme = Theme.of(context).colorScheme;
    final sftpAvailable = tabs.activeSsh != null;
    return SizedBox(
      width: 300,
      child: Column(
        children: [
          // ---- pane switcher ----
          Material(
            color: scheme.surfaceContainerLow,
            child: Row(
              children: [
                _PaneButton(
                  label: '会话',
                  icon: Icons.bookmarks_outlined,
                  selected: _pane == 0,
                  onTap: () => setState(() => _pane = 0),
                ),
                _PaneButton(
                  label: 'SFTP',
                  icon: Icons.folder_outlined,
                  selected: _pane == 1,
                  enabled: sftpAvailable,
                  onTap: () => setState(() => _pane = 1),
                ),
                _PaneButton(
                  label: '宏',
                  icon: Icons.auto_awesome,
                  selected: _pane == 2,
                  onTap: () => setState(() => _pane = 2),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: scheme.outlineVariant),
          Expanded(
            child: switch (_pane) {
              1 => sftpAvailable
                  ? SftpPanel(ssh: tabs.activeSsh!, app: app)
                  : const _PlaceholderPane(
                      icon: Icons.folder_off_outlined,
                      message: '连接 SSH 会话后自动显示远程文件'),
              2 => MacroPanel(tabs: tabs, app: app),
              _ => _SessionsPane(tabs: tabs, app: app),
            },
          ),
        ],
      ),
    );
  }
}

class _PaneButton extends StatelessWidget {
  const _PaneButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                width: 2,
                color: selected && enabled
                    ? scheme.primary
                    : Colors.transparent,
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 15,
                  color: enabled
                      ? (selected ? scheme.primary : scheme.onSurfaceVariant)
                      : scheme.outlineVariant),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: enabled
                      ? (selected ? scheme.primary : scheme.onSurfaceVariant)
                      : scheme.outlineVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaceholderPane extends StatelessWidget {
  const _PlaceholderPane({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 40, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Sessions pane: group tree with connect / edit / duplicate / delete
// ---------------------------------------------------------------------
class _SessionsPane extends StatelessWidget {
  const _SessionsPane({required this.tabs, required this.app});

  final TabsState tabs;
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sessions = app.repo.sessions.toList()
      ..sort((a, b) {
        final g = a.group.compareTo(b.group);
        return g != 0 ? g : a.name.compareTo(b.name);
      });
    final groups = app.repo.groups.toList()..sort();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () async {
                    final p = await showSessionEditorDialog(context, app);
                    if (p != null) {
                      await app.repo.upsert(p);
                      tabs.open(p);
                    }
                  },
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('新建会话', style: TextStyle(fontSize: 12)),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(32),
                  ),
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: scheme.outlineVariant),
        Expanded(
          child: sessions.isEmpty
              ? const _PlaceholderPane(
                  icon: Icons.bookmark_add_outlined,
                  message: '还没有保存的会话，点击上方按钮或使用快速连接创建',
                )
              : ListView(
                  children: [
                    if (groups.isEmpty)
                      for (final s in sessions.where((s) => s.group.isEmpty))
                        _SessionTile(
                            session: s, tabs: tabs, app: app),
                    for (final g in groups)
                      ExpansionTile(
                        dense: true,
                        initiallyExpanded: true,
                        tilePadding:
                            const EdgeInsets.symmetric(horizontal: 10),
                        title: Text(g,
                            style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600)),
                        children: [
                          for (final s in sessions
                              .where((s) => s.group == g))
                            _SessionTile(session: s, tabs: tabs, app: app),
                        ],
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({
    required this.session,
    required this.tabs,
    required this.app,
  });

  final SessionProfile session;
  final TabsState tabs;
  final AppState app;

  IconData get _typeIcon => switch (session.type) {
        SessionType.ssh => Icons.computer_outlined,
        SessionType.localShell => Icons.terminal,
        SessionType.telnet => Icons.lan_outlined,
        SessionType.serial => Icons.usb,
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final opened =
        tabs.tabs.any((t) => t.session.profile.id == session.id);

    return GestureDetector(
      onSecondaryTapUp: (d) => _menu(context, d.globalPosition),
      child: ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        contentPadding: const EdgeInsets.only(left: 14, right: 6),
        leading: Icon(_typeIcon,
            size: 17,
            color: opened ? scheme.primary : scheme.onSurfaceVariant),
        title: Text(session.name,
            style: const TextStyle(fontSize: 12.5),
            overflow: TextOverflow.ellipsis),
        subtitle: Text(session.subtitle,
            style: TextStyle(
                fontSize: 10.5, color: scheme.onSurfaceVariant),
            overflow: TextOverflow.ellipsis),
        onLongPress: () => _menu(context),
        onTap: () {
          if (session.type == SessionType.serial) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('串口会话需要 libserialport 运行库（规划中）')));
            return;
          }
          tabs.open(session);
        },
      ),
    );
  }

  void _menu(BuildContext context, [Offset? pos]) {
    showMenu<String>(
      context: context,
      position: pos == null
          ? const RelativeRect.fromLTRB(200, 300, 200, 300)
          : RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx + 1, pos.dy + 1),
      items: const [
        PopupMenuItem(value: 'connect', child: Text('连接')),
        PopupMenuItem(value: 'edit', child: Text('编辑…')),
        PopupMenuItem(value: 'duplicate', child: Text('复制会话')),
        PopupMenuItem(value: 'delete', child: Text('删除')),
      ],
    ).then((v) async {
      if (v == null || !context.mounted) return;
      switch (v) {
        case 'connect':
          tabs.open(session);
        case 'edit':
          final updated =
              await showSessionEditorDialog(context, app, initial: session);
          if (updated != null) await app.repo.upsert(updated);
        case 'duplicate':
          final map = session.toJson();
          map['id'] = 's-${DateTime.now().millisecondsSinceEpoch}';
          map['name'] = '${session.name} 副本';
          await app.repo.upsert(SessionProfile.fromJson(map));
        case 'delete':
          final ok = await showConfirmDialog(
            context,
            title: '删除会话',
            message: '确定删除会话 "${session.name}" 吗？',
            dangerLabel: '删除',
          );
          if (ok && context.mounted) await app.repo.remove(session.id);
      }
    });
  }
}
