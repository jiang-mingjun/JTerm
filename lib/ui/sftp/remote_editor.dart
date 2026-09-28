import 'package:flutter/material.dart';

import '../../core/ssh/sftp_service.dart';

/// Edits a remote text file over the existing SFTP channel.
Future<void> showRemoteEditor(
  BuildContext context, {
  required SftpService sftp,
  required String path,
}) async {
  String initial;
  try {
    initial = await sftp.readText(path);
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('无法打开: $error')),
      );
    }
    return;
  }
  if (!context.mounted) return;
  final controller = TextEditingController(text: initial);
  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(path.split('/').last, style: const TextStyle(fontSize: 15)),
      content: SizedBox(
        width: 720,
        height: 460,
        child: TextField(
          controller: controller,
          maxLines: null,
          expands: true,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('保存到远程'),
        ),
      ],
    ),
  );
  if (saved != true) {
    controller.dispose();
    return;
  }
  try {
    await sftp.writeText(path, controller.text);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已写回远程文件')),
      );
    }
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败: $error')),
      );
    }
  }
  controller.dispose();
}
