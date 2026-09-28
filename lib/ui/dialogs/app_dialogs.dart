/// Shared dialogs: text/secret prompt, host-key confirmation, confirm.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/ssh/ssh_connection.dart';

Future<String?> showPromptDialog(
  BuildContext context, {
  required String title,
  String? label,
  String? initialValue,
  bool obscure = false,
  bool multiline = false,
  String confirmText = '确定',
}) {
  final controller = TextEditingController(text: initialValue ?? '');
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title, style: const TextStyle(fontSize: 16)),
      content: TextField(
        controller: controller,
        obscureText: obscure,
        maxLines: multiline ? 5 : 1,
        autofocus: true,
        decoration: InputDecoration(labelText: label ?? title),
        onSubmitted: (v) => Navigator.of(ctx).pop(v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(controller.text),
          child: Text(confirmText),
        ),
      ],
    ),
  );
}

Future<bool> showYesNoDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmText = '保存',
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title, style: const TextStyle(fontSize: 16)),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('不保存'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(confirmText),
        ),
      ],
    ),
  );
  return result ?? false;
}

Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String dangerLabel = '删除',
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title, style: const TextStyle(fontSize: 16)),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(ctx).colorScheme.error,
          ),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(dangerLabel),
        ),
      ],
    ),
  );
  return r ?? false;
}

Future<HostKeyDecision> showHostKeyDialog(
  BuildContext context, {
  required String host,
  required String keyType,
  required String fingerprint,
  required bool changed,
}) async {
  final r = await showDialog<HostKeyDecision>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: Text(changed ? '主机密钥已改变！' : '未知的主机密钥',
          style: const TextStyle(fontSize: 16)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (changed)
            const Text(
              '警告：该主机返回的密钥与已保存的不一致，可能存在中间人攻击风险！',
              style: TextStyle(color: Colors.redAccent),
            )
          else
            const Text('首次连接该主机，请核对密钥指纹：'),
          const SizedBox(height: 12),
          SelectableText('主机: $host\n类型: $keyType\n指纹: $fingerprint'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(HostKeyDecision.reject),
          child: const Text('拒绝'),
        ),
        OutlinedButton(
          onPressed: () => Navigator.of(ctx).pop(HostKeyDecision.trustOnce),
          child: const Text('仅本次信任'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(ctx).pop(HostKeyDecision.trustAndSave),
          child: const Text('信任并保存'),
        ),
      ],
    ),
  );
  return r ?? HostKeyDecision.reject;
}

/// Small helper dialog with a row of labeled text fields.
Future<Map<String, String>?> showFormDialog(
  BuildContext context, {
  required String title,
  required List<FormFieldSpec> fields,
}) {
  final controllers = {
    for (final f in fields) f.key: TextEditingController(text: f.initial ?? '')
  };
  return showDialog<Map<String, String>>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title, style: const TextStyle(fontSize: 16)),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final f in fields)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: TextField(
                    controller: controllers[f.key],
                    keyboardType: f.numeric
                        ? TextInputType.number
                        : TextInputType.text,
                    inputFormatters: f.numeric
                        ? [FilteringTextInputFormatter.digitsOnly]
                        : null,
                    decoration: InputDecoration(
                      labelText: f.label,
                      helperText: f.helper,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(ctx).pop({for (final e in controllers.entries) e.key: e.value.text}),
          child: const Text('确定'),
        ),
      ],
    ),
  );
}

Future<List<String>?> showKeyboardInteractiveDialog(
  BuildContext context, {
  required String name,
  required String instruction,
  required List<({String prompt, bool echo})> prompts,
}) {
  final controllers = [
    for (final _ in prompts) TextEditingController(),
  ];
  return showDialog<List<String>>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: Text(name.isEmpty ? '服务器询问' : name,
          style: const TextStyle(fontSize: 16)),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (instruction.isNotEmpty) ...[
              Text(instruction, style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 8),
            ],
            for (var i = 0; i < prompts.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: TextField(
                  controller: controllers[i],
                  obscureText: !prompts[i].echo,
                  autofocus: i == 0,
                  decoration: InputDecoration(
                    labelText: prompts[i].prompt,
                    isDense: true,
                  ),
                  onSubmitted: prompts.length == 1
                      ? (_) => Navigator.of(ctx)
                          .pop([for (final c in controllers) c.text])
                      : null,
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(ctx).pop([for (final c in controllers) c.text]),
          child: const Text('继续'),
        ),
      ],
    ),
  );
}

class FormFieldSpec {
  FormFieldSpec(
    this.key,
    this.label, {
    this.initial,
    this.numeric = false,
    this.helper,
  });

  final String key;
  final String label;
  final String? initial;
  final bool numeric;
  final String? helper;
}
