import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/models/session_profile.dart';
import '../core/store/credential_vault.dart';
import '../core/terminal/terminal_session.dart';
import '../state/app_state.dart';
import '../state/tabs_state.dart';
import '../ui/dialogs/app_dialogs.dart';
import '../ui/forward/forward_dialog.dart';
import '../ui/session/session_edit_dialog.dart';
import '../ui/session/session_sidebar.dart';
import '../ui/settings/settings_page.dart';
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeVaultGate());
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
      body: Column(
        children: [
          _Toolbar(onQuickConnect: _quickConnect, tabs: tabs, app: app),
          Expanded(
            child: Row(
              children: [
                SessionSidebar(tabs: tabs, app: app),
                const VerticalDivider(width: 1),
                Expanded(child: _buildTerminalArea(app, scheme)),
              ],
            ),
          ),
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
              ? _EmptyState(onNewTab: _openLocalShell, tabs: tabs, app: app)
              : IndexedStack(
                  index: tabs.tabs
                      .indexWhere((t) => t.id == tabs.activeId)
                      .clamp(0, tabs.tabs.length - 1),
                  children: [
                    for (final t in tabs.tabs)
                      TerminalPage(tab: t, tabs: tabs),
                  ],
                ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.onNewTab,
    required this.tabs,
    required this.app,
  });

  final Future<void> Function() onNewTab;
  final TabsState tabs;
  final AppState app;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.terminal, size: 64,
              color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 12),
          const Text('暂无打开的会话'),
          const SizedBox(height: 4),
          const Text('使用左上角快速连接，或从左侧会话面板选择一个会话',
              style: TextStyle(fontSize: 12)),
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            onPressed: onNewTab,
            icon: const Icon(Icons.terminal),
            label: const Text('打开本地终端'),
          ),
        ],
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.onQuickConnect,
    required this.tabs,
    required this.app,
  });

  final Future<void> Function(String) onQuickConnect;
  final TabsState tabs;
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ctrl = TextEditingController();

    return Material(
      color: scheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            Icon(Icons.terminal, color: scheme.primary),
            const SizedBox(width: 6),
            Text('JTerm',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: scheme.primary,
                )),
            const SizedBox(width: 16),
            SizedBox(
              width: 300,
              height: 36,
              child: TextField(
                controller: ctrl,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: '快速连接 user@host:port',
                  prefixIcon: const Icon(Icons.bolt, size: 18),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                ),
                style: const TextStyle(fontSize: 13),
                onSubmitted: onQuickConnect,
              ),
            ),
            const SizedBox(width: 6),
            FilledButton(
              onPressed: () => onQuickConnect(ctrl.text),
              style: FilledButton.styleFrom(
                minimumSize: const Size(48, 36),
              ),
              child: const Text('连接'),
            ),
            const VerticalDivider(indent: 8, endIndent: 8),
            IconButton(
              tooltip: '新建会话 (SSH/串口/Telnet)',
              icon: const Icon(Icons.add_box_outlined, size: 20),
              onPressed: () async {
                final profile = await showSessionEditorDialog(context, app);
                if (profile != null) {
                  tabs.open(profile);
                }
              },
            ),
            IconButton(
              tooltip: '端口转发管理',
              icon: const Icon(Icons.alt_route, size: 20),
              onPressed: () => showForwardDialog(context, tabs),
            ),
            IconButton(
              tooltip: tabs.showSftpPanel ? '隐藏 SFTP 面板' : '显示 SFTP 面板',
              icon: Icon(
                tabs.showSftpPanel
                    ? Icons.space_dashboard_outlined
                    : Icons.space_dashboard,
                size: 20,
              ),
              onPressed: tabs.toggleSftpPanel,
            ),
            const Spacer(),
            IconButton(
              tooltip: '设置',
              icon: const Icon(Icons.settings_outlined, size: 20),
              onPressed: () => showDialog(
                context: context,
                builder: (_) => const SettingsPage(),
              ),
            ),
            IconButton(
              tooltip: app.vault.state == VaultState.unlocked
                  ? '锁定凭据保险库'
                  : '凭据保险库未解锁',
              icon: Icon(
                app.vault.state == VaultState.unlocked
                    ? Icons.lock_outline
                    : Icons.lock_open_outlined,
                size: 20,
              ),
              onPressed: app.vault.state == VaultState.unlocked
                  ? app.lockVault
                  : null,
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
        height: 26,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Text('$text · ${active?.title ?? "-"}',
                  style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
              const Spacer(),
              if (tabs.broadcastActive)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Text('广播已开启 (${tabs.broadcastIds.length})',
                      style: TextStyle(
                          fontSize: 11, color: scheme.tertiary)),
                ),
              Text('UTF-8', style: TextStyle(fontSize: 11, color: scheme.outline)),
            ],
          ),
        ),
      ),
    );
  }
}
