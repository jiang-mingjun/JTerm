import 'package:flutter/material.dart';

import '../../core/forward/port_forward_engine.dart';
import '../../core/models/forward_rule.dart';
import '../../state/tabs_state.dart';

/// Manage active port forwards of the current SSH session and its saved rules.
Future<void> showForwardDialog(BuildContext context, TabsState tabs) {
  return showDialog<void>(
    context: context,
    builder: (_) => _ForwardDialog(tabs: tabs),
  );
}

class _ForwardDialog extends StatefulWidget {
  const _ForwardDialog({required this.tabs});

  final TabsState tabs;

  @override
  State<_ForwardDialog> createState() => _ForwardDialogState();
}

class _ForwardDialogState extends State<_ForwardDialog> {
  @override
  Widget build(BuildContext context) {
    final ssh = widget.tabs.activeSsh;
    final scheme = Theme.of(context).colorScheme;

    if (ssh == null) {
      return AlertDialog(
        title: const Text('端口转发', style: TextStyle(fontSize: 16)),
        content: const Text('请先连接一个 SSH 会话再管理隧道'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('关闭')),
        ],
      );
    }

    final engine = ssh.forwardEngine;
    final profileRules = ssh.profile.forwards;
    final List<ActiveForward> activeFwd = engine?.active ?? [];

    return AlertDialog(
      title: Text('端口转发 - ${ssh.profile.name}',
          style: const TextStyle(fontSize: 16)),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('会话规则',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 6),
            if (profileRules.isEmpty)
              const Text('（在会话编辑器中配置 -L/-R/-D 规则）',
                  style: TextStyle(fontSize: 12)),
            for (final rule in profileRules)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  rule.type == ForwardType.local
                      ? Icons.south_east
                      : rule.type == ForwardType.remote
                          ? Icons.north_east
                          : Icons.shuffle,
                  size: 18,
                  color: scheme.primary,
                ),
                title: Text(rule.describe(),
                    style: const TextStyle(fontSize: 12.5)),
                subtitle: Text(
                  _stateOf(rule, engine),
                  style: TextStyle(
                      fontSize: 11,
                      color: _isOn(rule, engine)
                          ? Colors.green
                          : scheme.outline),
                ),
                trailing: IconButton(
                  icon: Icon(
                    _isOn(rule, engine) ? Icons.stop : Icons.play_arrow,
                    size: 18,
                  ),
                  onPressed: () async {
                    if (_isOn(rule, engine)) {
                      await engine?.stopAll();
                      // restart all other enabled rules
                      if (engine != null) {
                        for (final r in profileRules) {
                          if (r.id != rule.id &&
                              r.enabled &&
                              r.autoStart &&
                              r.isValid) {
                            await engine.start(r);
                          }
                        }
                      }
                    } else {
                      await engine?.start(rule);
                    }
                    setState(() {});
                  },
                ),
              ),
            const Divider(),
            const Text('活跃隧道',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 6),
            if (activeFwd.isEmpty)
              const Text('（暂无活跃隧道）',
                  style: TextStyle(fontSize: 12)),
            for (final a in activeFwd)
              ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    a.active ? Icons.check_circle : Icons.error_outline,
                    size: 16,
                    color: a.active ? Colors.green : scheme.error,
                  ),
                  title: Text(a.rule.describe(),
                      style: const TextStyle(fontSize: 12)),
                  subtitle: a.error != null
                      ? Text(a.error!,
                          style: TextStyle(fontSize: 10, color: scheme.error))
                      : null,
                ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('关闭')),
      ],
    );
  }

  bool _isOn(ForwardRule rule, PortForwardEngine? engine) {
    if (engine == null) return false;
    return engine.active.any((a) => a.rule.id == rule.id && a.active);
  }

  String _stateOf(ForwardRule rule, PortForwardEngine? engine) =>
      _isOn(rule, engine) ? '运行中' : '已停止';
}
