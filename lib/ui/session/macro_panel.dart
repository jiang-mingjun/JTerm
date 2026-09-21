import 'package:flutter/material.dart';

import '../../core/models/macro.dart';
import '../../state/app_state.dart';
import '../../state/tabs_state.dart';
import '../dialogs/app_dialogs.dart';

/// Macro pane: list recorded command sequences and replay them into the
/// active session (or all broadcast sessions).
class MacroPanel extends StatelessWidget {
  const MacroPanel({super.key, required this.tabs, required this.app});

  final TabsState tabs;
  final AppState app;

  Future<void> _run(Macro macro) async {
    for (final step in macro.steps) {
      tabs.sendCommand(step.command);
      await Future<void>.delayed(Duration(milliseconds: step.delayMs));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () => _edit(context, null),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('新建宏', style: TextStyle(fontSize: 12)),
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(32)),
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: scheme.outlineVariant),
        Expanded(
          child: app.repo.macros.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('宏可以保存一组常用命令序列，一键发送到会话',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12)),
                  ),
                )
              : ListView.builder(
                  itemCount: app.repo.macros.length,
                  itemBuilder: (context, i) {
                    final m = app.repo.macros[i];
                    return GestureDetector(
                      onSecondaryTapUp: (d) =>
                          _menu(context, m, d.globalPosition),
                      child: ListTile(
                        dense: true,
                        leading: const Icon(Icons.auto_awesome, size: 16),
                        title: Text(m.name,
                            style: const TextStyle(fontSize: 12.5)),
                        subtitle: Text(
                          m.steps.map((s) => s.command).take(2).join(' ; '),
                          style:
                              TextStyle(fontSize: 10, color: scheme.outline),
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => _run(m),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _menu(BuildContext context, Macro m, Offset pos) {
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx + 1, pos.dy + 1),
      items: const [
        PopupMenuItem(value: 'run', child: Text('立即执行')),
        PopupMenuItem(value: 'edit', child: Text('编辑…')),
        PopupMenuItem(value: 'delete', child: Text('删除')),
      ],
    ).then((v) async {
      if (v == null || !context.mounted) return;
      switch (v) {
        case 'run':
          await _run(m);
        case 'edit':
          _edit(context, m);
        case 'delete':
          final ok = await showConfirmDialog(context,
              title: '删除宏', message: '确定删除 "${m.name}" 吗？');
          if (ok && context.mounted) await app.repo.deleteMacro(m.id);
      }
    });
  }

  Future<void> _edit(BuildContext context, Macro? initial) async {
    final name = await showPromptDialog(
      context,
      title: '宏名称',
      initialValue: initial?.name,
    );
    if (name == null || name.isEmpty || !context.mounted) return;

    final commandsText = await showPromptDialog(
      context,
      title: '命令序列（每行一条，可用 |延时毫秒 单独一行控制节奏）',
      initialValue: initial?.steps
          .map((s) =>
              s.delayMs == 200 ? s.command : '${s.command}|${s.delayMs}')
          .join('\n'),
      multiline: true,
    );
    if (commandsText == null || !context.mounted) return;

    final steps = <MacroStep>[];
    for (final line in commandsText.split('\n')) {
      final t = line.trim();
      if (t.isEmpty) continue;
      if (t.contains('|')) {
        final parts = t.split('|');
        final delay = int.tryParse(parts.last) ?? 200;
        steps.add(MacroStep(
            command: parts.sublist(0, parts.length - 1).join('|'),
            delayMs: delay));
      } else {
        steps.add(MacroStep(command: t));
      }
    }
    if (steps.isEmpty) return;

    await app.repo.saveMacro(Macro(
      id: initial?.id ?? 'm-${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      steps: steps,
    ));
  }
}
