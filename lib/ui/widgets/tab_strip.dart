import 'package:flutter/material.dart';

import '../../core/terminal/terminal_session.dart';
import '../../state/tabs_state.dart';
import '../dialogs/app_dialogs.dart';

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
      color: scheme.surfaceContainerLow,
      child: SizedBox(
        height: 40,
        child: Row(
          children: [
            const SizedBox(width: 8),
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
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: IconButton(
                icon: const Icon(Icons.add_rounded, size: 18),
                tooltip: '新标签 (Ctrl+T)',
                onPressed: onNewTab,
                style: IconButton.styleFrom(
                  backgroundColor: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
                  minimumSize: const Size(28, 28),
                  fixedSize: const Size(28, 28),
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
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

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 3),
      child: Material(
        color: selected ? scheme.surfaceContainerHighest : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => tabs.activate(tabId),
          onSecondaryTapUp: (d) => _menu(context, d.globalPosition),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 220),
            padding: const EdgeInsets.only(left: 10, right: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected ? scheme.primary.withValues(alpha: 0.55) : Colors.transparent,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: dot,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: dot.withValues(alpha: 0.45), blurRadius: 6),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    title,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (broadcast) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.campaign_rounded, size: 13, color: scheme.tertiary),
                ],
                InkWell(
                  onTap: () => tabs.close(tabId),
                  customBorder: const CircleBorder(),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(Icons.close_rounded, size: 14, color: scheme.outline),
                  ),
                ),
              ],
            ),
          ),
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
        const PopupMenuItem(value: 'splitH', child: Text('左右分屏')),
        const PopupMenuItem(value: 'splitV', child: Text('上下分屏')),
        const PopupMenuItem(value: 'unsplit', child: Text('取消分屏')),
        const PopupMenuItem(value: 'duplicate', child: Text('复制标签')),
        const PopupMenuItem(value: 'rename', child: Text('重命名标签')),
        const PopupMenuItem(value: 'reconnect', child: Text('重新连接')),
        const PopupMenuItem(value: 'closeOthers', child: Text('关闭其他标签')),
        const PopupMenuItem(value: 'close', child: Text('关闭标签')),
      ],
    ).then((v) async {
      if (v == null) return;
      switch (v) {
        case 'broadcast':
          tabs.toggleBroadcast(tabId);
        case 'splitH':
          tabs.setSplit(PaneSplit.horizontal, tabId);
        case 'splitV':
          tabs.setSplit(PaneSplit.vertical, tabId);
        case 'unsplit':
          tabs.setSplit(PaneSplit.none, tabId);
        case 'duplicate':
          tabs.duplicate(tabId);
        case 'rename':
          if (!context.mounted) return;
          final name = await showPromptDialog(
            context,
            title: '标签名称',
            initialValue: title,
          );
          if (name != null) tabs.rename(tabId, name);
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
