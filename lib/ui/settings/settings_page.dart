import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/store/credential_vault.dart';
import '../../state/app_state.dart';

/// Application settings dialog.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final settings = app.settings;
    final scheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: const Text('设置', style: TextStyle(fontSize: 16)),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ---- appearance ----
              Text('外观',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: scheme.primary)),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('主题色  '),
                  for (final c in [
                    0xFF0F766E, 0xFF2563EB, 0xFF7C3AED,
                    0xFFDB2777, 0xFFEA580C, 0xFF16A34A,
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: InkWell(
                        onTap: () => settings.themeSeed = c,
                        customBorder: const CircleBorder(),
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: Color(c),
                            shape: BoxShape.circle,
                            border: settings.themeSeed == c
                                ? Border.all(
                                    color: scheme.onSurface, width: 2.5)
                                : null,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('深色模式', style: TextStyle(fontSize: 13)),
                value: settings.darkMode,
                onChanged: (v) => settings.darkMode = v,
              ),
              const Divider(),

              // ---- terminal ----
              Text('终端',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: scheme.primary)),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('字体大小'),
                  Expanded(
                    child: Slider(
                      value: settings.fontSize,
                      min: 9,
                      max: 24,
                      divisions: 15,
                      label: settings.fontSize.toStringAsFixed(0),
                      onChanged: (v) => settings.fontSize = v,
                    ),
                  ),
                  Text(settings.fontSize.toStringAsFixed(0)),
                ],
              ),
              TextFormField(
                initialValue: settings.fontFamily,
                decoration: const InputDecoration(
                  labelText: '等宽字体族 (留空使用默认，如 JetBrains Mono, Noto Sans Mono)',
                  isDense: true,
                ),
                style: const TextStyle(fontSize: 13),
                onChanged: (v) => settings.fontFamily = v.trim(),
              ),
              const Divider(),

              // ---- storage / vault ----
              Text('数据',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: scheme.primary)),
              const SizedBox(height: 6),
              Text('配置目录: ${app.dataDir}',
                  style: TextStyle(fontSize: 11, color: scheme.outline)),
              const SizedBox(height: 6),
              if (app.vault.state == VaultState.unlocked) ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '凭据保险库：已解锁，${app.vault.entries.length} 条凭据',
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    ),
                    OutlinedButton(
                      onPressed: () {
                        app.lockVault();
                        Navigator.of(context).pop();
                      },
                      child: const Text('锁定'),
                    ),
                  ],
                ),
                for (final e in app.vault.entries)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.key, size: 16),
                    title: Text(e.name, style: const TextStyle(fontSize: 12.5)),
                    subtitle: Text(e.username ?? '',
                        style: TextStyle(
                            fontSize: 10.5, color: scheme.outline)),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, size: 16),
                      onPressed: () => app.vault.delete(e.id),
                    ),
                  ),
              ] else
                const Text('凭据保险库未解锁（应用重启后可解锁）',
                    style: TextStyle(fontSize: 12.5)),
              const SizedBox(height: 8),
              const Divider(),
              Text('关于',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: scheme.primary)),
              const SizedBox(height: 6),
              const Text(
                'JTerm v0.1.0 - Linux 全功能 SSH 客户端\n核心层纯 Dart 实现，未来可移植至鸿蒙 (HarmonyOS)',
                style: TextStyle(fontSize: 11.5),
              ),
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('完成'),
        ),
      ],
    );
  }
}
