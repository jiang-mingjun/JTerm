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
    return ColoredBox(
      color: scheme.surfaceContainerLow,
      child: SizedBox(
      width: 292,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: Row(
                  children: [
                    _PaneButton(
                      label: '会话',
                      icon: Icons.dns_rounded,
                      selected: _pane == 0,
                      onTap: () => setState(() => _pane = 0),
                    ),
                    _PaneButton(
                      label: '文件',
                      icon: Icons.folder_rounded,
                      selected: _pane == 1,
                      enabled: sftpAvailable,
                      onTap: () => setState(() => _pane = 1),
                    ),
                    _PaneButton(
                      label: '宏',
                      icon: Icons.bolt_rounded,
                      selected: _pane == 2,
                      onTap: () => setState(() => _pane = 2),
                    ),
                  ],
                ),
              ),
            ),
          ),
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
    final active = selected && enabled;
    return Expanded(
      child: Material(
        color: active ? scheme.surfaceContainerHigh : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon,
                    size: 15,
                    color: enabled
                        ? (active ? scheme.primary : scheme.onSurfaceVariant)
                        : scheme.outline),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    color: enabled
                        ? (active ? scheme.onSurface : scheme.onSurfaceVariant)
                        : scheme.outline,
                  ),
                ),
              ],
            ),
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
class _SessionsPane extends StatefulWidget {
  const _SessionsPane({required this.tabs, required this.app});

  final TabsState tabs;
  final AppState app;

  @override
  State<_SessionsPane> createState() => _SessionsPaneState();
}

class _SessionsPaneState extends State<_SessionsPane> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final tabs = widget.tabs;
    final app = widget.app;
    final scheme = Theme.of(context).colorScheme;
    final needle = _query.trim().toLowerCase();
    final sessions = app.repo.sessions.where((session) {
      if (needle.isEmpty) return true;
      return session.name.toLowerCase().contains(needle) ||
          session.subtitle.toLowerCase().contains(needle) ||
          session.group.toLowerCase().contains(needle) ||
          session.notes.toLowerCase().contains(needle);
    }).toList()
      ..sort((a, b) {
        final g = a.group.compareTo(b.group);
        return g != 0 ? g : a.name.compareTo(b.name);
      });
    final recent = app.repo.sessions.where((s) => s.lastUsedMs > 0).toList()
      ..sort((a, b) => b.lastUsedMs.compareTo(a.lastUsedMs));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () async {
                    final profile = await showSessionEditorDialog(context, app);
                    if (profile != null) {
                      await app.repo.upsert(profile);
                      tabs.open(profile);
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
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
          child: SizedBox(
            height: 32,
            child: TextField(
              style: const TextStyle(fontSize: 12),
              decoration: const InputDecoration(
                isDense: true,
                hintText: '搜索会话、主机、分组',
                prefixIcon: Icon(Icons.search, size: 16),
                contentPadding: EdgeInsets.zero,
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
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
                    if (needle.isEmpty && recent.isNotEmpty) ...[
                      const _SectionLabel('最近'),
                      for (final session in recent.take(6))
                        _SessionTile(session: session, tabs: tabs, app: app),
                    ],
                    ..._groupWidgets(_tree(sessions), tabs, app, 0),
                  ],
                ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 2),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class _GroupNode {
  _GroupNode(this.name, this.path);

  final String name;
  final String path;
  final List<_GroupNode> children = [];
  final List<SessionProfile> sessions = [];
}

_GroupNode _tree(List<SessionProfile> sessions) {
  final root = _GroupNode('', '');
  for (final session in sessions) {
    if (session.group.isEmpty) {
      root.sessions.add(session);
      continue;
    }
    final parts = session.group.split('/').where((p) => p.isNotEmpty).toList();
    var node = root;
    final acc = <String>[];
    for (final part in parts) {
      acc.add(part);
      final path = acc.join('/');
      var next = node.children.where((c) => c.path == path).firstOrNull;
      if (next == null) {
        next = _GroupNode(part, path);
        node.children.add(next);
      }
      node = next;
    }
    node.sessions.add(session);
  }
  return root;
}

List<Widget> _groupWidgets(
  _GroupNode node,
  TabsState tabs,
  AppState app,
  int depth,
) {
  final widgets = <Widget>[];
  if (node.path.isEmpty) {
    widgets.addAll([
      for (final session in node.sessions)
        _SessionTile(session: session, tabs: tabs, app: app),
    ]);
  }
  for (final child in node.children) {
    widgets.add(ExpansionTile(
      dense: true,
      initiallyExpanded: depth < 2,
      tilePadding: EdgeInsets.only(left: 8.0 + depth * 8, right: 8),
      title: Text(
        child.name,
        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
      ),
      children: [
        for (final session in child.sessions)
          _SessionTile(session: session, tabs: tabs, app: app),
        ..._groupWidgets(child, tabs, app, depth + 1),
      ],
    ));
  }
  if (node.path.isNotEmpty) return widgets;
  return widgets;
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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Material(
        color: opened
            ? scheme.primary.withValues(alpha: 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => tabs.open(session),
          onLongPress: () => _menu(context),
          onSecondaryTapUp: (d) => _menu(context, d.globalPosition),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 7, 8, 7),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: opened
                        ? scheme.primary.withValues(alpha: 0.18)
                        : scheme.surfaceContainerHighest.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(_typeIcon,
                      size: 15,
                      color: opened ? scheme.primary : scheme.onSurfaceVariant),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(session.name,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurface,
                          ),
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 1),
                      Text(session.subtitle,
                          style: TextStyle(
                              fontSize: 10.5, color: scheme.onSurfaceVariant),
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
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
