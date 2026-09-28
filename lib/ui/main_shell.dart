import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/models/session_profile.dart';
import '../core/store/credential_vault.dart';
import '../core/terminal/terminal_session.dart';
import '../state/app_state.dart';
import '../state/tabs_state.dart';
import '../core/models/macro.dart';
import '../ui/dialogs/app_dialogs.dart';
import '../ui/forward/forward_dialog.dart';
import '../ui/session/session_edit_dialog.dart';
import '../ui/session/session_sidebar.dart';
import '../ui/settings/settings_page.dart';
import '../ui/tools/tool_dialogs.dart';
import '../ui/widgets/tab_strip.dart';
import '../ui/terminal/terminal_page.dart';

/// The main window: toolbar + left sidebar + terminal tabs + status bar.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  late final TabsState tabs;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    tabs = TabsState(app);
    WidgetsBinding.instance.addPostFrameCallback((_) => _startup());
  }

  Future<void> _startup() async {
    await _maybeVaultGate();
    if (!mounted) return;
    final app = context.read<AppState>();
    for (final profile in app.repo.sessions.where((s) => s.autoConnect)) {
      tabs.open(profile);
    }
  }

  /// Ask for the vault master password on startup when a vault exists.
  Future<void> _maybeVaultGate() async {
    final app = context.read<AppState>();
    if (app.vault.state == VaultState.locked) {
      final pw = await showPromptDialog(
        context,
        title: '解锁凭据保险库',
        label: '主密码',
        obscure: true,
        confirmText: '解锁',
      );
      if (pw != null && pw.isNotEmpty) {
        final ok = await app.unlockVault(pw);
        if (!ok && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('主密码错误，保险库仍处于锁定状态')),
          );
        }
      }
    }
  }

  Future<void> _quickConnect(String text) async {
    text = text.trim();
    if (text.isEmpty) return;
    final app = context.read<AppState>();

    // Formats: user@host, user@host:port, host, host:port
    var user = '';
    var hostPort = text;
    if (text.contains('@')) {
      final parts = text.split('@');
      user = parts.first;
      hostPort = parts.sublist(1).join('@');
    }
    var port = 22;
    var host = hostPort;
    if (hostPort.contains(':') && !hostPort.contains(']')) {
      final seg = hostPort.split(':');
      host = seg.first;
      port = int.tryParse(seg.last) ?? 22;
    }
    if (host.isEmpty) return;

    final profile = SessionProfile(
      id: 'qc-${DateTime.now().millisecondsSinceEpoch}',
      name: text,
      type: SessionType.ssh,
      host: host,
      port: port,
      username: user.isEmpty ? null : user,
      createdMs: DateTime.now().millisecondsSinceEpoch,
    );
    tabs.open(profile);
    await app.repo.upsert(profile);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;

    return ChangeNotifierProvider.value(
      value: tabs,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyT, control: true):
              () => _openLocalShell(),
          const SingleActivator(LogicalKeyboardKey.keyW, control: true): () {
            if (tabs.activeId != null) tabs.close(tabs.activeId!);
          },
          const SingleActivator(LogicalKeyboardKey.tab, control: true):
              () => tabs.next(),
          const SingleActivator(LogicalKeyboardKey.tab,
              control: true, shift: true): () => tabs.previous(),
        },
        child: Focus(autofocus: true, child: _buildBody(app, scheme)),
      ),
    );
  }

  Future<void> _openLocalShell() async {
    final profile = SessionProfile(
      id: 'local-${DateTime.now().millisecondsSinceEpoch}',
      name: '本地终端',
      type: SessionType.localShell,
      createdMs: DateTime.now().millisecondsSinceEpoch,
    );
    tabs.open(profile);
  }

  Widget _buildBody(AppState app, ColorScheme scheme) {
    return Scaffold(
      backgroundColor: scheme.surface,
      body: Column(
        children: [
          _Toolbar(onQuickConnect: _quickConnect, tabs: tabs, app: app),
          Divider(height: 1, color: scheme.outlineVariant),
          Expanded(
            child: Row(
              children: [
                SessionSidebar(tabs: tabs, app: app),
                VerticalDivider(width: 1, color: scheme.outlineVariant),
                Expanded(child: _buildTerminalArea(app, scheme)),
              ],
            ),
          ),
          Divider(height: 1, color: scheme.outlineVariant),
          _StatusBar(tabs: tabs),
        ],
      ),
    );
  }

  Widget _buildTerminalArea(AppState app, ColorScheme scheme) {
    return Column(
      children: [
        TabStrip(tabs: tabs, onNewTab: _openLocalShell),
        Divider(height: 1, color: scheme.outlineVariant),
        Expanded(
          child: tabs.tabs.isEmpty
              ? _EmptyState(onNewTab: _openLocalShell)
              : _TerminalPanes(tabs: tabs),
        ),
      ],
    );
  }
}

class _TerminalPanes extends StatelessWidget {
  const _TerminalPanes({required this.tabs});

  final TabsState tabs;

  @override
  Widget build(BuildContext context) {
    final secondaryId =
        tabs.split == PaneSplit.none ? null : tabs.splitTabId;
    final primary = <Widget>[];
    Widget? secondary;
    for (final tab in tabs.tabs) {
      final page = TerminalPage(key: tab.pageKey, tab: tab, tabs: tabs);
      final pinned = secondaryId != null &&
          tab.id == secondaryId &&
          tab.id != tabs.activeId;
      if (pinned) {
        secondary = page;
      } else {
        primary.add(Offstage(
          offstage: tab.id != tabs.activeId,
          child: page,
        ));
      }
    }
    final left = Stack(
      fit: StackFit.expand,
      children: primary.isEmpty ? const [SizedBox.shrink()] : primary,
    );
    if (secondary == null) return left;
    final divider = tabs.split == PaneSplit.horizontal
        ? const VerticalDivider(width: 1)
        : const Divider(height: 1);
    final panes = <Widget>[
      Expanded(child: left),
      divider,
      Expanded(child: secondary),
    ];
    return tabs.split == PaneSplit.horizontal
        ? Row(children: panes)
        : Column(children: panes);
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onNewTab});

  final Future<void> Function() onNewTab;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      scheme.primary.withValues(alpha: 0.9),
                      scheme.tertiary.withValues(alpha: 0.75),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: scheme.primary.withValues(alpha: 0.28),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Icon(Icons.terminal_rounded,
                    size: 34, color: scheme.onPrimary),
              ),
              const SizedBox(height: 22),
              Text('准备好连接了',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.4,
                    color: scheme.onSurface,
                  )),
              const SizedBox(height: 8),
              Text(
                '从左侧打开一个会话，或在上方输入 user@host 直接连上去。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.45,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 22),
              FilledButton.icon(
                onPressed: onNewTab,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('打开本地终端'),
              ),
              const SizedBox(height: 22),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: const [
                  _HintChip(keys: 'Ctrl+T', label: '本地终端'),
                  _HintChip(keys: 'Ctrl+W', label: '关闭标签'),
                  _HintChip(keys: 'Ctrl+F', label: '查找'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HintChip extends StatelessWidget {
  const _HintChip({required this.keys, required this.label});

  final String keys;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(keys,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: scheme.primary,
              )),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _Toolbar extends StatefulWidget {
  const _Toolbar({
    required this.onQuickConnect,
    required this.tabs,
    required this.app,
  });

  final Future<void> Function(String) onQuickConnect;
  final TabsState tabs;
  final AppState app;

  @override
  State<_Toolbar> createState() => _ToolbarState();
}

class _ToolbarState extends State<_Toolbar> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tabs = widget.tabs;
    final app = widget.app;

    return Material(
      color: scheme.surfaceContainerLow,
      child: SizedBox(
        height: 56,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.terminal_rounded,
                    size: 16, color: scheme.onPrimary),
              ),
              const SizedBox(width: 8),
              Text('JTerm',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                    color: scheme.onSurface,
                  )),
              const SizedBox(width: 16),
              SizedBox(
                width: 340,
                height: 36,
                child: TextField(
                  controller: _ctrl,
                  decoration: InputDecoration(
                    hintText: 'user@host 或 host:port',
                    prefixIcon: Icon(Icons.bolt_rounded,
                        size: 18, color: scheme.primary),
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  ),
                  style: const TextStyle(fontSize: 13),
                  onSubmitted: widget.onQuickConnect,
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => widget.onQuickConnect(_ctrl.text),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(64, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
                child: const Text('连接'),
              ),
              const SizedBox(width: 10),
              _ToolGroup(
                children: [
                  _ToolIcon(
                    tooltip: '新建会话',
                    icon: Icons.add_rounded,
                    onPressed: () async {
                      final profile =
                          await showSessionEditorDialog(context, app);
                      if (profile != null) tabs.open(profile);
                    },
                  ),
                  _ToolIcon(
                    tooltip: '端口转发',
                    icon: Icons.alt_route_rounded,
                    onPressed: () => showForwardDialog(context, tabs),
                  ),
                  _ToolIcon(
                    tooltip: '左右分屏',
                    icon: Icons.vertical_split_rounded,
                    selected: tabs.split == PaneSplit.horizontal,
                    onPressed: tabs.activeId == null
                        ? null
                        : () => tabs.setSplit(
                              tabs.split == PaneSplit.horizontal
                                  ? PaneSplit.none
                                  : PaneSplit.horizontal,
                              tabs.activeId!,
                            ),
                  ),
                  _ToolIcon(
                    tooltip: '上下分屏',
                    icon: Icons.horizontal_split_rounded,
                    selected: tabs.split == PaneSplit.vertical,
                    onPressed: tabs.activeId == null
                        ? null
                        : () => tabs.setSplit(
                              tabs.split == PaneSplit.vertical
                                  ? PaneSplit.none
                                  : PaneSplit.vertical,
                              tabs.activeId!,
                            ),
                  ),
                  _ToolIcon(
                    tooltip: tabs.recordingMacro ? '停止并保存宏' : '录制宏',
                    icon: tabs.recordingMacro
                        ? Icons.stop_circle_rounded
                        : Icons.fiber_manual_record_rounded,
                    color: tabs.recordingMacro ? scheme.error : null,
                    onPressed: () => _toggleRecord(context, tabs, app),
                  ),
                  _ToolIcon(
                    tooltip: '工具',
                    icon: Icons.construction_rounded,
                    onPressed: () => showToolMenu(context, app),
                  ),
                  _ToolIcon(
                    tooltip: tabs.showSftpPanel ? '隐藏文件面板' : '显示文件面板',
                    icon: Icons.folder_rounded,
                    selected: tabs.showSftpPanel,
                    onPressed: tabs.toggleSftpPanel,
                  ),
                ],
              ),
              const Spacer(),
              _ToolIcon(
                tooltip: '设置',
                icon: Icons.settings_rounded,
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => const SettingsPage(),
                ),
              ),
              _ToolIcon(
                tooltip: app.vault.state == VaultState.unlocked
                    ? '锁定凭据保险库'
                    : '凭据保险库未解锁',
                icon: app.vault.state == VaultState.unlocked
                    ? Icons.lock_rounded
                    : Icons.lock_open_rounded,
                color: app.vault.state == VaultState.unlocked
                    ? scheme.primary
                    : scheme.outline,
                onPressed: app.vault.state == VaultState.unlocked
                    ? app.lockVault
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolGroup extends StatelessWidget {
  const _ToolGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Row(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }
}

class _ToolIcon extends StatelessWidget {
  const _ToolIcon({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.selected = false,
    this.color,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool selected;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      icon: Icon(
        icon,
        size: 18,
        color: color ??
            (selected ? scheme.primary : scheme.onSurfaceVariant),
      ),
    );
  }
}

Future<void> _toggleRecord(
  BuildContext context,
  TabsState tabs,
  AppState app,
) async {
  if (!tabs.recordingMacro) {
    tabs.beginRecording();
    return;
  }
  final steps = tabs.stopRecording();
  if (steps.isEmpty || !context.mounted) {
    if (context.mounted && steps.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有录到命令')),
      );
    }
    return;
  }
  final name = await showPromptDialog(
    context,
    title: '保存录制的宏',
    initialValue: '新建宏',
  );
  if (name == null || name.trim().isEmpty) return;
  await app.repo.saveMacro(Macro(
    id: 'm-${DateTime.now().millisecondsSinceEpoch}',
    name: name.trim(),
    steps: steps,
  ));
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.icon, required this.label, this.color});

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tint = color ?? scheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 280),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: tint.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: tint),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: tint),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.tabs});

  final TabsState tabs;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = tabs.active;
    final s = active?.session;
    final (icon, text, color) = switch (s?.status) {
      SessionStatus.connecting => (Icons.cloud_sync_outlined, '连接中…', scheme.tertiary),
      SessionStatus.connected => (Icons.cloud_done_outlined, '已连接', Colors.green),
      SessionStatus.reconnecting => (Icons.sync, '重连中…', Colors.orange),
      SessionStatus.failed => (Icons.error_outline, '失败: ${s?.failMessage}', scheme.error),
      SessionStatus.disconnected => (Icons.cloud_off_outlined, '已断开', scheme.outline),
      null => (Icons.info_outline, '无活动会话', scheme.outline),
    };

    return Material(
      color: scheme.surfaceContainerLow,
      child: SizedBox(
        height: 30,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  '${active?.title ?? '空闲'}  ·  $text',
                  style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Spacer(),
              if (active?.session.remoteCwd.isNotEmpty == true)
                _StatusChip(icon: Icons.folder_outlined, label: active!.session.remoteCwd),
              if (tabs.recordingMacro)
                _StatusChip(icon: Icons.fiber_manual_record, label: '录制中', color: scheme.error),
              if (tabs.broadcastActive)
                _StatusChip(
                  icon: Icons.campaign_outlined,
                  label: '广播 ${tabs.broadcastIds.length}',
                  color: scheme.tertiary,
                ),
              if (active?.session.logPath != null)
                const _StatusChip(icon: Icons.description_outlined, label: '日志'),
              const SizedBox(width: 8),
              Text(
                s == null ? 'UTF-8' : '${s.columns}×${s.rows}',
                style: TextStyle(
                  fontSize: 11,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: scheme.outline,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
