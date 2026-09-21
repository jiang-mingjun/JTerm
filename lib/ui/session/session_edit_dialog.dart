import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../core/models/forward_rule.dart';
import '../../core/models/session_profile.dart';
import '../../core/store/credential_vault.dart';
import '../../state/app_state.dart';

/// Full session editor dialog - the equivalent of the MobaXterm session
/// settings sheet (basic, credentials, network, SSH browser settings).
Future<SessionProfile?> showSessionEditorDialog(
  BuildContext context,
  AppState app, {
  SessionProfile? initial,
}) {
  return showDialog<SessionProfile>(
    context: context,
    builder: (_) => _SessionEditor(app: app, initial: initial),
  );
}

class _SessionEditor extends StatefulWidget {
  const _SessionEditor({required this.app, this.initial});

  final AppState app;
  final SessionProfile? initial;

  @override
  State<_SessionEditor> createState() => _SessionEditorState();
}

class _SessionEditorState extends State<_SessionEditor> {
  late SessionProfile p;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    p = widget.initial?.copyWith() ??
        SessionProfile(
          id: 's-${DateTime.now().millisecondsSinceEpoch}',
          name: '',
          type: SessionType.ssh,
          createdMs: DateTime.now().millisecondsSinceEpoch,
        );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isSsh = p.type == SessionType.ssh;
    final isSerial = p.type == SessionType.serial;

    return AlertDialog(
      title: Text(widget.initial == null ? '新建会话' : '编辑会话',
          style: const TextStyle(fontSize: 16)),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ---- type ----
                SegmentedButton<SessionType>(
                  segments: const [
                    ButtonSegment(
                        value: SessionType.ssh,
                        label: Text('SSH'),
                        icon: Icon(Icons.computer, size: 16)),
                    ButtonSegment(
                        value: SessionType.localShell,
                        label: Text('本地'),
                        icon: Icon(Icons.terminal, size: 16)),
                    ButtonSegment(
                        value: SessionType.telnet,
                        label: Text('Telnet'),
                        icon: Icon(Icons.lan, size: 16)),
                    ButtonSegment(
                        value: SessionType.serial,
                        label: Text('串口'),
                        icon: Icon(Icons.usb, size: 16)),
                  ],
                  selected: {p.type},
                  onSelectionChanged: (s) => setState(() => p.type = s.first),
                  showSelectedIcon: false,
                ),
                const SizedBox(height: 12),

                TextFormField(
                  initialValue: p.name,
                  decoration: const InputDecoration(
                      labelText: '会话名称 *', isDense: true),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? '必填' : null,
                  onChanged: (v) => p.name = v.trim(),
                ),
                const SizedBox(height: 8),

                if (p.type == SessionType.localShell) ...[
                  const Text('本地终端将在当前用户的登录 shell 中打开。',
                      style: TextStyle(fontSize: 12)),
                ] else if (isSerial) ...[
                  TextFormField(
                    initialValue: p.serialDevice ?? '',
                    decoration: const InputDecoration(
                        labelText: '串口设备 (如 /dev/ttyUSB0)', isDense: true),
                    onChanged: (v) => p.serialDevice = v,
                  ),
                  DropdownButtonFormField<int>(
                    initialValue: p.serialBaudRate,
                    decoration:
                        const InputDecoration(labelText: '波特率', isDense: true),
                    items: const [
                      DropdownMenuItem(value: 9600, child: Text('9600')),
                      DropdownMenuItem(value: 19200, child: Text('19200')),
                      DropdownMenuItem(value: 38400, child: Text('38400')),
                      DropdownMenuItem(value: 57600, child: Text('57600')),
                      DropdownMenuItem(value: 115200, child: Text('115200')),
                    ],
                    onChanged: (v) => p.serialBaudRate = v ?? 115200,
                  ),
                ] else ...[
                  Row(children: [
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        initialValue: p.host ?? '',
                        decoration: InputDecoration(
                            labelText: isSsh ? '主机地址 *' : '主机地址',
                            isDense: true),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? '必填'
                            : null,
                        onChanged: (v) => p.host = v.trim(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        initialValue: '${p.port}',
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                            labelText: '端口',
                            isDense: true,
                            hintText: isSsh ? '22' : '23'),
                        onChanged: (v) =>
                            p.port = int.tryParse(v) ?? (isSsh ? 22 : 23),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  TextFormField(
                    initialValue: p.username ?? '',
                    decoration: InputDecoration(
                        labelText: isSsh ? '用户名' : '用户名 (NVT 登录)',
                        isDense: true),
                    onChanged: (v) => p.username = v.trim(),
                  ),
                ],
                const SizedBox(height: 8),
                TextFormField(
                  initialValue: p.group,
                  decoration: const InputDecoration(
                      labelText: '分组 (用 / 分隔层级，如 生产/华东)',
                      isDense: true),
                  onChanged: (v) => p.group = v.trim(),
                ),

                if (isSsh) ...[
                  const Divider(height: 24),
                  Text('SSH 认证',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: scheme.primary)),
                  const SizedBox(height: 8),
                  SegmentedButton<AuthMethod>(
                    segments: const [
                      ButtonSegment(value: AuthMethod.password, label: Text('密码')),
                      ButtonSegment(
                          value: AuthMethod.publicKey, label: Text('密钥')),
                    ],
                    selected: {p.authMethod},
                    onSelectionChanged: (s) =>
                        setState(() => p.authMethod = s.first),
                    showSelectedIcon: false,
                  ),
                  const SizedBox(height: 8),
                  if (p.authMethod == AuthMethod.publicKey)
                    Row(children: [
                      Expanded(
                        child: TextFormField(
                          initialValue: p.privateKeyPath ?? '',
                          decoration: const InputDecoration(
                              labelText: '私钥文件 (~/.ssh/id_ed25519)',
                              isDense: true),
                          onChanged: (v) => p.privateKeyPath = v.trim(),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.folder_open, size: 18),
                        onPressed: () async {
                          final f = await openFile();
                          if (f != null) {
                            setState(() => p.privateKeyPath = f.path);
                          }
                        },
                      ),
                    ]),
                  _VaultPicker(p: p, app: widget.app),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String?>(
                    initialValue: p.jumpViaSessionId,
                    decoration: const InputDecoration(
                        labelText: '跳板机 (经由另一 SSH 会话连接)',
                        isDense: true),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('不使用')),
                      for (final s in widget.app.repo.sessions
                          .where((s) =>
                              s.type == SessionType.ssh &&
                              s.id != p.id &&
                              s.jumpViaSessionId == null))
                        DropdownMenuItem(value: s.id, child: Text(s.name)),
                    ],
                    onChanged: (v) => p.jumpViaSessionId = v,
                  ),
                  SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('X11 转发 (连接本机 X 服务)',
                        style: TextStyle(fontSize: 13)),
                    value: p.x11Forwarding,
                    onChanged: (v) => setState(() => p.x11Forwarding = v),
                  ),
                  SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('自动打开 SFTP 浏览器',
                        style: TextStyle(fontSize: 13)),
                    value: p.autoOpenSftp,
                    onChanged: (v) => setState(() => p.autoOpenSftp = v),
                  ),
                  TextFormField(
                    initialValue: p.startupCommand,
                    decoration: const InputDecoration(
                        labelText: '登录后自动执行命令', isDense: true),
                    onChanged: (v) => p.startupCommand = v,
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<ReconnectPolicy>(
                    initialValue: p.reconnect,
                    decoration: const InputDecoration(
                        labelText: '断线重连策略', isDense: true),
                    items: const [
                      DropdownMenuItem(
                          value: ReconnectPolicy.onDrop, child: Text('断开后重连')),
                      DropdownMenuItem(
                          value: ReconnectPolicy.never, child: Text('从不')),
                    ],
                    onChanged: (v) => p.reconnect = v ?? ReconnectPolicy.onDrop,
                  ),
                  const Divider(height: 24),
                  Row(
                    children: [
                      Text('端口转发规则',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: scheme.primary)),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.add, size: 16),
                        tooltip: '添加转发',
                        onPressed: () => setState(() => p.forwards.add(
                              ForwardRule(
                                id: 'f-${DateTime.now().millisecondsSinceEpoch}',
                                type: ForwardType.local,
                                localPort: 8080,
                                remoteHost: '127.0.0.1',
                                remotePort: 80,
                              ),
                            )),
                      ),
                    ],
                  ),
                  for (final f in p.forwards)
                    _ForwardRuleTile(
                      rule: f,
                      onChanged: () => setState(() {}),
                      onRemove: () =>
                          setState(() => p.forwards.remove(f)),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.of(context).pop(p);
            }
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}

/// Pick a saved credential entry from the vault (when unlocked).
class _VaultPicker extends StatelessWidget {
  const _VaultPicker({required this.p, required this.app});

  final SessionProfile p;
  final AppState app;

  @override
  Widget build(BuildContext context) {
    if (app.vault.state != VaultState.unlocked) {
      return const Padding(
        padding: EdgeInsets.only(top: 8),
        child: Text('提示：解锁凭据保险库后可选择已保存的密码/密钥口令',
            style: TextStyle(fontSize: 11)),
      );
    }
    return DropdownButtonFormField<String?>(
      initialValue: p.credentialId,
      decoration: const InputDecoration(
          labelText: '保存的凭据 (保险库)', isDense: true),
      items: [
        const DropdownMenuItem(value: null, child: Text('连接时询问')),
        for (final e in app.vault.entries)
          DropdownMenuItem(value: e.id, child: Text(e.name)),
      ],
      onChanged: (v) => p.credentialId = v,
    );
  }
}

class _ForwardRuleTile extends StatelessWidget {
  const _ForwardRuleTile({
    required this.rule,
    required this.onChanged,
    required this.onRemove,
  });

  final ForwardRule rule;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          DropdownButton<ForwardType>(
            value: rule.type,
            underline: const SizedBox.shrink(),
            items: const [
              DropdownMenuItem(
                  value: ForwardType.local, child: Text('-L 本地')),
              DropdownMenuItem(
                  value: ForwardType.remote, child: Text('-R 远程')),
              DropdownMenuItem(
                  value: ForwardType.dynamic, child: Text('-D 动态')),
            ],
            onChanged: (v) {
              rule.type = v ?? ForwardType.local;
              onChanged();
            },
          ),
          const SizedBox(width: 6),
          Expanded(
            child: TextFormField(
              initialValue: '${rule.localPort}',
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                isDense: true,
                hintText: rule.type == ForwardType.remote
                    ? '远程端口'
                    : '本地端口',
              ),
              style: const TextStyle(fontSize: 12),
              onChanged: (v) =>
                  rule.localPort = int.tryParse(v) ?? rule.localPort,
            ),
          ),
          if (rule.type != ForwardType.dynamic) ...[
            const SizedBox(width: 6),
            Expanded(
              flex: 2,
              child: TextFormField(
                initialValue: rule.remoteHost ?? '',
                decoration: const InputDecoration(
                    isDense: true, hintText: '目标主机'),
                style: const TextStyle(fontSize: 12),
                onChanged: (v) => rule.remoteHost = v,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: TextFormField(
                initialValue: '${rule.remotePort ?? ''}',
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    isDense: true, hintText: '目标端口'),
                style: const TextStyle(fontSize: 12),
                onChanged: (v) =>
                    rule.remotePort = int.tryParse(v) ?? rule.remotePort,
              ),
            ),
          ],
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 15),
            onPressed: onRemove,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}
