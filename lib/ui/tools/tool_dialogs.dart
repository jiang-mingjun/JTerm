import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/ssh/openssh_keygen.dart';
import '../../core/ssh/ssh_config_import.dart';
import '../../core/store/credential_vault.dart';
import '../../core/tools/net_probe.dart';
import '../../state/app_state.dart';
import '../dialogs/app_dialogs.dart';

Future<void> showToolMenu(BuildContext context, AppState app) async {
  final action = await showDialog<String>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('工具', style: TextStyle(fontSize: 16)),
      children: [
        _item(ctx, 'keygen', Icons.vpn_key_outlined, '生成 SSH 密钥'),
        _item(ctx, 'sshconfig', Icons.download_outlined, '导入 OpenSSH 配置'),
        _item(ctx, 'import', Icons.file_open_outlined, '导入会话'),
        _item(ctx, 'export', Icons.save_alt_outlined, '导出会话'),
        _item(ctx, 'hosts', Icons.verified_user_outlined, '已知主机'),
        _item(ctx, 'vault', Icons.lock_outline, '凭据管理'),
        _item(ctx, 'net', Icons.lan_outlined, '网络探测'),
        _item(ctx, 'keys', Icons.keyboard_outlined, '快捷键'),
      ],
    ),
  );
  if (action == null || !context.mounted) return;
  switch (action) {
    case 'keygen':
      await _keygen(context);
    case 'sshconfig':
      await _importSshConfig(context, app);
    case 'import':
      await _importSessions(context, app);
    case 'export':
      await _exportSessions(context, app);
    case 'hosts':
      await _knownHosts(context, app);
    case 'vault':
      await _vault(context, app);
    case 'net':
      await _net(context);
    case 'keys':
      await _shortcuts(context);
  }
}

Widget _item(BuildContext ctx, String value, IconData icon, String label) {
  return SimpleDialogOption(
    onPressed: () => Navigator.of(ctx).pop(value),
    child: Row(
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 10),
        Text(label),
      ],
    ),
  );
}

Future<void> _keygen(BuildContext context) async {
  final home = Platform.environment['HOME'] ?? '';
  var type = 'ed25519';
  final pathCtrl = TextEditingController(
    text: '$home/.ssh/id_ed25519_jterm',
  );
  final commentCtrl = TextEditingController(text: 'jterm');
  final passCtrl = TextEditingController();
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: const Text('生成 SSH 密钥', style: TextStyle(fontSize: 16)),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: type,
                decoration: const InputDecoration(labelText: '类型', isDense: true),
                items: const [
                  DropdownMenuItem(value: 'ed25519', child: Text('ed25519')),
                  DropdownMenuItem(value: 'rsa', child: Text('RSA 4096')),
                ],
                onChanged: (value) => setLocal(() => type = value ?? 'ed25519'),
              ),
              TextField(
                controller: pathCtrl,
                decoration: const InputDecoration(
                  labelText: '私钥路径',
                  isDense: true,
                ),
              ),
              TextField(
                controller: commentCtrl,
                decoration: const InputDecoration(labelText: '注释', isDense: true),
              ),
              TextField(
                controller: passCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '口令（可留空）',
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('生成'),
          ),
        ],
      ),
    ),
  );
  if (result != true) {
    pathCtrl.dispose();
    commentCtrl.dispose();
    passCtrl.dispose();
    return;
  }
  try {
    final generated = await generateOpenSshKey(
      path: pathCtrl.text.trim(),
      type: type,
      comment: commentCtrl.text.trim(),
      passphrase: passCtrl.text,
    );
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('公钥', style: TextStyle(fontSize: 16)),
        content: SizedBox(
          width: 520,
          child: SelectableText(
            generated.publicKey.isEmpty ? '已写入 ${generated.privatePath}' : generated.publicKey,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: generated.publicKey));
              Navigator.of(ctx).pop();
            },
            child: const Text('复制并关闭'),
          ),
        ],
      ),
    );
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error')),
      );
    }
  }
  pathCtrl.dispose();
  commentCtrl.dispose();
  passCtrl.dispose();
}

Future<void> _importSshConfig(BuildContext context, AppState app) async {
  final home = Platform.environment['HOME'] ?? '';
  final defaultFile = File('$home/.ssh/config');
  final choice = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('导入 OpenSSH 配置', style: TextStyle(fontSize: 16)),
      content: Text(
        defaultFile.existsSync()
            ? '从 $home/.ssh/config 导入 Host 条目，或选择其他文件。'
            : '未找到 ~/.ssh/config，请选择一个配置文件。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('取消'),
        ),
        if (defaultFile.existsSync())
          FilledButton.tonal(
            onPressed: () => Navigator.of(ctx).pop('default'),
            child: const Text('使用默认文件'),
          ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop('pick'),
          child: const Text('选择文件'),
        ),
      ],
    ),
  );
  if (choice == null || !context.mounted) return;
  File file;
  if (choice == 'default') {
    file = defaultFile;
  } else {
    final picked = await openFile();
    if (picked == null) return;
    file = File(picked.path);
  }
  final text = await file.readAsString();
  final result = await importSshConfig(text, app.repo, home: home);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('已导入 ${result.created} 个会话，跳过 ${result.skipped} 个')),
  );
}

Future<void> _importSessions(BuildContext context, AppState app) async {
  final picked = await openFile(
    acceptedTypeGroups: const [
      XTypeGroup(label: 'JSON', extensions: ['json']),
    ],
  );
  if (picked == null || !context.mounted) return;
  try {
    final data = jsonDecode(await File(picked.path).readAsString());
    if (data is! Map<String, dynamic>) {
      throw StateError('文件格式不正确');
    }
    final count = await app.repo.importBundle(data);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已导入 $count 项')),
    );
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导入失败: $error')),
      );
    }
  }
}

Future<void> _exportSessions(BuildContext context, AppState app) async {
  final location = await getSaveLocation(suggestedName: 'jterm-sessions.json');
  if (location == null) return;
  final text = const JsonEncoder.withIndent('  ').convert(app.repo.exportBundle());
  await File(location.path).writeAsString(text);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('已导出到 ${location.path}')),
  );
}

Future<void> _knownHosts(BuildContext context, AppState app) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('已知主机', style: TextStyle(fontSize: 16)),
      content: SizedBox(
        width: 520,
        height: 360,
        child: app.knownHosts.hosts.isEmpty
            ? const Center(child: Text('还没有受信主机'))
            : ListView(
                children: [
                  for (final host in app.knownHosts.hosts)
                    ListTile(
                      dense: true,
                      title: Text(host.host, style: const TextStyle(fontSize: 13)),
                      subtitle: Text(
                        '${host.keyType}  ${host.fingerprint}',
                        style: const TextStyle(fontSize: 11),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, size: 16),
                        onPressed: () async {
                          await app.knownHosts.forget(host.host);
                          if (ctx.mounted) Navigator.of(ctx).pop();
                          if (context.mounted) _knownHosts(context, app);
                        },
                      ),
                    ),
                ],
              ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}

Future<void> _vault(BuildContext context, AppState app) async {
  if (app.vault.state == VaultState.locked) {
    final password = await showPromptDialog(
      context,
      title: '解锁凭据保险库',
      obscure: true,
    );
    if (password == null || password.isEmpty) return;
    final ok = await app.unlockVault(password);
    if (!ok) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('主密码错误')),
        );
      }
      return;
    }
  } else if (app.vault.state == VaultState.empty) {
    final password = await showPromptDialog(
      context,
      title: '创建保险库主密码',
      obscure: true,
    );
    if (password == null || password.length < 4) return;
    await app.createVault(password);
  }
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => _VaultEditor(app: app),
  );
}

class _VaultEditor extends StatefulWidget {
  const _VaultEditor({required this.app});

  final AppState app;

  @override
  State<_VaultEditor> createState() => _VaultEditorState();
}

class _VaultEditorState extends State<_VaultEditor> {
  Future<void> _edit({VaultEntry? existing}) async {
    final name = TextEditingController(text: existing?.name ?? '');
    final user = TextEditingController(text: existing?.username ?? '');
    final password = TextEditingController(text: existing?.password ?? '');
    final key = TextEditingController(text: existing?.keyPath ?? '');
    final pass = TextEditingController(text: existing?.passphrase ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? '新建凭据' : '编辑凭据',
            style: const TextStyle(fontSize: 16)),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: '名称', isDense: true),
              ),
              TextField(
                controller: user,
                decoration: const InputDecoration(labelText: '用户名', isDense: true),
              ),
              TextField(
                controller: password,
                obscureText: true,
                decoration: const InputDecoration(labelText: '密码', isDense: true),
              ),
              TextField(
                controller: key,
                decoration: const InputDecoration(labelText: '私钥路径', isDense: true),
              ),
              TextField(
                controller: pass,
                obscureText: true,
                decoration: const InputDecoration(labelText: '私钥口令', isDense: true),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (ok == true && name.text.trim().isNotEmpty) {
      await widget.app.vault.addOrUpdate(VaultEntry(
        id: existing?.id ?? 'c-${DateTime.now().millisecondsSinceEpoch}',
        name: name.text.trim(),
        username: user.text.trim(),
        password: password.text,
        keyPath: key.text.trim(),
        passphrase: pass.text,
      ));
      widget.app.refresh();
      if (mounted) setState(() {});
    }
    name.dispose();
    user.dispose();
    password.dispose();
    key.dispose();
    pass.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.app.vault.entries;
    return AlertDialog(
      title: const Text('凭据保险库', style: TextStyle(fontSize: 16)),
      content: SizedBox(
        width: 460,
        height: 360,
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                onPressed: () => _edit(),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('新建'),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                children: [
                  for (final entry in entries)
                    ListTile(
                      dense: true,
                      title: Text(entry.name),
                      subtitle: Text(entry.username ?? ''),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 16),
                            onPressed: () => _edit(existing: entry),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 16),
                            onPressed: () async {
                              await widget.app.vault.delete(entry.id);
                              widget.app.refresh();
                              if (mounted) setState(() {});
                            },
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}

Future<void> _net(BuildContext context) async {
  final hostCtrl = TextEditingController();
  final portCtrl = TextEditingController(text: '22');
  await showDialog<void>(
    context: context,
    builder: (ctx) => _NetDialog(hostCtrl: hostCtrl, portCtrl: portCtrl),
  );
  hostCtrl.dispose();
  portCtrl.dispose();
}

class _NetDialog extends StatefulWidget {
  const _NetDialog({required this.hostCtrl, required this.portCtrl});

  final TextEditingController hostCtrl;
  final TextEditingController portCtrl;

  @override
  State<_NetDialog> createState() => _NetDialogState();
}

class _NetDialogState extends State<_NetDialog> {
  String _output = '输入主机后探测 TCP 端口或 ping。';
  bool _busy = false;

  Future<void> _run(Future<ProbeResult> future) async {
    setState(() => _busy = true);
    final result = await future;
    if (!mounted) return;
    final ms = result.elapsed?.inMilliseconds;
    setState(() {
      _busy = false;
      _output = '${result.ok ? '成功' : '失败'}${ms == null ? '' : '  ${ms}ms'}\n\n${result.detail}';
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('网络探测', style: TextStyle(fontSize: 16)),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: widget.hostCtrl,
                    decoration: const InputDecoration(labelText: '主机', isDense: true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: widget.portCtrl,
                    decoration: const InputDecoration(labelText: '端口', isDense: true),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                FilledButton.tonal(
                  onPressed: _busy
                      ? null
                      : () {
                          final host = widget.hostCtrl.text.trim();
                          final port = int.tryParse(widget.portCtrl.text) ?? 22;
                          if (host.isEmpty) return;
                          _run(probeTcp(host, port));
                        },
                  child: const Text('TCP'),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  onPressed: _busy
                      ? null
                      : () {
                          final host = widget.hostCtrl.text.trim();
                          if (host.isEmpty) return;
                          _run(probePing(host));
                        },
                  child: const Text('Ping'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 180,
              width: double.infinity,
              child: SingleChildScrollView(
                child: SelectableText(
                  _output,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}

Future<void> _shortcuts(BuildContext context) {
  const rows = [
    ['Ctrl+T', '新建本地终端'],
    ['Ctrl+W', '关闭当前标签'],
    ['Ctrl+Tab / Ctrl+Shift+Tab', '切换标签'],
    ['Ctrl+F', '查找回滚内容'],
    ['Ctrl+Shift+C / V', '复制 / 粘贴'],
    ['Ctrl+点击', '打开终端里的链接'],
  ];
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('快捷键', style: TextStyle(fontSize: 16)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 180,
                    child: Text(row[0],
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 12)),
                  ),
                  Expanded(child: Text(row[1])),
                ],
              ),
            ),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}
