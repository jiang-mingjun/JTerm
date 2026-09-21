import 'package:flutter/material.dart';

import '../../core/terminal/terminal_session.dart';
import '../../state/tabs_state.dart';

/// Horizontal strip of terminal tabs with context menu, MobaXterm style.
class TabStrip extends StatelessWidget {
  const TabStrip({
    super.key,
    required this.tabs,
    required this.onNewTab,
  });

  final TabsState tabs;
  final Future<void> Function() onNewTab;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLowest,
      child: SizedBox(
        height: 34,
        child: Row(
          children: [
            Expanded(
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: tabs.tabs.length,
                itemBuilder: (context, i) {
                  final tab = tabs.tabs[i];
                  return _TabChip(
                    tabs: tabs,
                    tabId: tab.id,
                    selected: tab.id == tabs.activeId,
                    title: tab.title,
                    status: tab.session.status,
                    broadcast: tabs.broadcastIds.contains(tab.id),
                  );
                },
              ),
            ),
            const VerticalDivider(width: 1),
            IconButton(
              icon: const Icon(Icons.add, size: 18),
              tooltip: '新标签 (Ctrl+T)',
              onPressed: onNewTab,
              constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
              padding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.tabs,
    required this.tabId,
    required this.title,
    required this.selected,
    required this.status,
    required this.broadcast,
  });

  final TabsState tabs;
  final String tabId;
  final String title;
  final bool selected;
  final SessionStatus status;
  final bool broadcast;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    Color dot;
    switch (status) {
      case SessionStatus.connected:
        dot = Colors.green;
      case SessionStatus.connecting:
      case SessionStatus.reconnecting:
        dot = Colors.orange;
      case SessionStatus.failed:
        dot = scheme.error;
      case SessionStatus.disconnected:
        dot = scheme.outline;
    }

    return InkWell(
      onTap: () => tabs.activate(tabId),
      onSecondaryTapUp: (d) => _menu(context, d.globalPosition),
      child: Container(
        padding: const EdgeInsets.only(left: 10, right: 4),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              width: 2.5,
              color: selected ? scheme.primary : Colors.transparent,
            ),
          ),
          color: selected ? scheme.surfaceContainerHigh : Colors.transparent,
        ),
        child: Row(
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
            const SizedBox(width: 7),
            Text(
              title,
              style: TextStyle(
                fontSize: 12.5,
                color: selected
                    ? scheme.onSurface
                    : scheme.onSurfaceVariant,
              ),
            ),
            if (broadcast) ...[
              const SizedBox(width: 4),
              Icon(Icons.campaign, size: 12, color: scheme.tertiary),
            ],
            const SizedBox(width: 2),
            InkWell(
              onTap: () => tabs.close(tabId),
              customBorder: const CircleBorder(),
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: Icon(Icons.close, size: 13, color: scheme.outline),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _menu(BuildContext context, Offset pos) {
    final controller = tabs.tabs.firstWhere((t) => t.id == tabId).session;
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx + 1, pos.dy + 1),
      items: [
        const PopupMenuItem(value: 'broadcast', child: Text('切换命令广播')),
        const PopupMenuItem(value: 'reconnect', child: Text('重新连接')),
        const PopupMenuItem(value: 'closeOthers', child: Text('关闭其他标签')),
        const PopupMenuItem(value: 'close', child: Text('关闭标签')),
      ],
    ).then((v) {
      if (v == null) return;
      switch (v) {
        case 'broadcast':
          tabs.toggleBroadcast(tabId);
        case 'reconnect':
          if (controller.status != SessionStatus.connecting) {
            // ignore: discarded_futures
            controller.disconnect().then((_) => controller.connect());
          }
        case 'closeOthers':
          for (final t in tabs.tabs.toList()) {
            if (t.id != tabId) tabs.close(t.id);
          }
        case 'close':
          tabs.close(tabId);
      }
    });
  }
}
