import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../core/ssh/sftp_service.dart';
import '../../core/terminal/ssh_terminal_session.dart';
import '../../core/terminal/terminal_session.dart';
import '../../state/app_state.dart';
import '../dialogs/app_dialogs.dart';
import 'remote_editor.dart';

/// Remote file browser attached to the active SSH session, with transfers.
class SftpPanel extends StatefulWidget {
  const SftpPanel({super.key, required this.ssh, required this.app});

  final SshTerminalSession ssh;
  final AppState app;

  @override
  State<SftpPanel> createState() => _SftpPanelState();
}

class _TransferJob {
  _TransferJob({
    required this.name,
    required this.upload,
    required this.total,
  });

  final String name;
  final bool upload;
  final int total;
  int done = 0;
  String? error;
  bool get finished => error != null || done >= total;
}

class _SftpPanelState extends State<SftpPanel> {
  String _path = '/';
  List<SftpEntry> _entries = [];
  bool _loading = false;
  String? _error;
  bool _follow = true;
  String _filter = '';
  final List<_TransferJob> _jobs = [];
  final _pathCtrl = TextEditingController();
  final _filterCtrl = TextEditingController();
  Timer? _refreshTicker;
  StreamSubscription<SessionEvent>? _cwdSub;

  SftpService? get _sftp => widget.ssh.sftp;

  @override
  void initState() {
    super.initState();
    _follow = widget.ssh.profile.followTerminalFolder;
    _listenCwd();
    final start = widget.ssh.remoteCwd.isNotEmpty
        ? widget.ssh.remoteCwd
        : (widget.ssh.sftp?.cwd.isNotEmpty == true ? widget.ssh.sftp!.cwd : '/');
    _load(start);
    _refreshTicker = Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (_jobs.any((j) => !j.finished)) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant SftpPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ssh != widget.ssh) {
      _follow = widget.ssh.profile.followTerminalFolder;
      _listenCwd();
      _load(widget.ssh.remoteCwd.isNotEmpty ? widget.ssh.remoteCwd : '/');
    }
  }

  void _listenCwd() {
    _cwdSub?.cancel();
    _cwdSub = widget.ssh.events.listen((event) {
      if (event is SessionCwdChanged && _follow && event.path != _path) {
        _load(event.path);
      }
    });
  }

  @override
  void dispose() {
    _refreshTicker?.cancel();
    _cwdSub?.cancel();
    _pathCtrl.dispose();
    _filterCtrl.dispose();
    super.dispose();
  }

  Future<void> _load(String path) async {
    final sftp = _sftp;
    if (sftp == null) return;
    setState(() {
      _loading = true;
      _error = null;
      _path = path;
      if (_pathCtrl.text != path) _pathCtrl.text = path;
    });
    try {
      final entries = await sftp.list(path);
      if (!mounted) return;
      setState(() => _entries = entries);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _download(SftpEntry e) async {
    final sftp = _sftp;
    if (sftp == null) return;
    var dirPath = widget.app.settings.downloadDir;
    if (dirPath.isEmpty) {
      final dir = await getDirectoryPath(confirmButtonText: '保存到此处');
      if (dir == null) return;
      dirPath = dir;
      widget.app.settings.downloadDir = dir;
    }
    final local = File('$dirPath/${e.name}');
    final job = _TransferJob(name: '↓ ${e.name}', upload: false, total: e.size);
    setState(() => _jobs.add(job));
    try {
      await sftp.downloadFile(
        e.fullPath,
        local,
        onProgress: (done, total) => job.done = done,
      );
    } catch (err) {
      job.error = err.toString();
    }
    if (mounted) setState(() {});
  }

  Future<void> _upload() async {
    final sftp = _sftp;
    if (sftp == null) return;
    final files = await openFiles();
    if (files.isEmpty) return;
    for (final f in files) {
      final local = File(f.path);
      final total = await local.length();
      final job = _TransferJob(
          name: '↑ ${f.name}', upload: true, total: total);
      setState(() => _jobs.add(job));
      try {
        await sftp.uploadFile(
          local,
          '$_path/${f.name}',
          onProgress: (done, t) => job.done = done,
        );
      } catch (err) {
        job.error = err.toString();
      }
      if (mounted) setState(() {});
    }
    _load(_path);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        // ---- path bar ----
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_upward, size: 16),
                tooltip: '上级目录',
                onPressed: () {
                  if (_path != '/') {
                    final parent =
                        _path.substring(0, _path.lastIndexOf('/'));
                    _load(parent.isEmpty ? '/' : parent);
                  }
                },
              ),
              IconButton(
                icon: const Icon(Icons.home_outlined, size: 16),
                tooltip: '主目录',
                onPressed: () => _load('.'),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 16),
                tooltip: '刷新',
                onPressed: () => _load(_path),
              ),
              Expanded(
                child: SizedBox(
                  height: 30,
                  child: TextField(
                    controller: _pathCtrl,
                    style: const TextStyle(fontSize: 11.5),
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    ),
                    onSubmitted: _load,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(
                  _follow ? Icons.my_location : Icons.location_disabled,
                  size: 16,
                ),
                tooltip: _follow ? '正在跟随终端目录' : '目录已固定',
                onPressed: () => setState(() => _follow = !_follow),
              ),
              IconButton(
                icon: Icon(
                  widget.app.settings.sftpBookmarks.contains(_path)
                      ? Icons.star
                      : Icons.star_border,
                  size: 16,
                ),
                tooltip: '收藏当前目录',
                onPressed: () {
                  widget.app.settings.toggleBookmark(_path);
                  setState(() {});
                },
              ),
              IconButton(
                icon: const Icon(Icons.upload_file, size: 16),
                tooltip: '上传文件',
                onPressed: _upload,
              ),
              IconButton(
                icon: const Icon(Icons.note_add_outlined, size: 16),
                tooltip: '新建文件',
                onPressed: _createFile,
              ),
            ],
          ),
        ),
        if (widget.app.settings.sftpBookmarks.isNotEmpty)
          SizedBox(
            height: 28,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final bookmark in widget.app.settings.sftpBookmarks)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: ActionChip(
                      label: Text(bookmark, style: const TextStyle(fontSize: 10)),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _load(bookmark),
                    ),
                  ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
          child: SizedBox(
            height: 28,
            child: TextField(
              controller: _filterCtrl,
              style: const TextStyle(fontSize: 12),
              decoration: const InputDecoration(
                isDense: true,
                hintText: '过滤文件名',
                prefixIcon: Icon(Icons.filter_alt_outlined, size: 14),
                contentPadding: EdgeInsets.zero,
              ),
              onChanged: (value) => setState(() => _filter = value.trim()),
            ),
          ),
        ),
        Divider(height: 1, color: scheme.outlineVariant),
        // ---- file list ----
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : _error != null
                  ? _ErrorRetry(error: _error!, onRetry: () => _load(_path))
                  : ListView.builder(
                      itemCount: _visible.length,
                      itemBuilder: (context, i) {
                        final e = _visible[i];
                        return _EntryTile(
                          entry: e,
                          onTap: () {
                            if (e.isDirectory || e.name == '..') {
                              _load(e.fullPath);
                            }
                          },
                          onMenu: (pos) => _entryMenu(context, e, pos),
                        );
                      },
                    ),
        ),
        // ---- transfer jobs ----
        if (_jobs.isNotEmpty)
          Container(
            constraints: const BoxConstraints(maxHeight: 130),
            color: scheme.surfaceContainerLow,
            child: ListView(
              shrinkWrap: true,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 4, 4, 0),
                  child: Row(
                    children: [
                      Text('传输任务 (${_jobs.where((j) => !j.finished).length} 进行中)',
                          style: const TextStyle(fontSize: 11)),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.delete_sweep_outlined, size: 14),
                        tooltip: '清除已完成',
                        onPressed: () => setState(
                            () => _jobs.removeWhere((j) => j.finished)),
                      ),
                    ],
                  ),
                ),
                for (final job in _jobs.take(6).toList().reversed)
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                    child: _JobBar(job: job),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  List<SftpEntry> get _visible {
    if (_filter.isEmpty) return _entries;
    final needle = _filter.toLowerCase();
    return _entries
        .where((e) => e.name == '..' || e.name.toLowerCase().contains(needle))
        .toList();
  }

  Future<void> _createFile() async {
    final sftp = _sftp;
    if (sftp == null) return;
    final name = await showPromptDialog(context, title: '新建文件');
    if (name == null || name.isEmpty) return;
    await sftp.writeText('$_path/$name', '');
    _load(_path);
  }

  Future<void> _downloadTree(SftpEntry entry, Directory local) async {
    final sftp = _sftp;
    if (sftp == null) return;
    await local.create(recursive: true);
    final children = await sftp.list(entry.fullPath);
    for (final child in children) {
      if (child.name == '.' || child.name == '..') continue;
      if (child.isDirectory) {
        await _downloadTree(child, Directory('${local.path}/${child.name}'));
      } else {
        final job = _TransferJob(
          name: '↓ ${child.name}',
          upload: false,
          total: child.size,
        );
        if (mounted) setState(() => _jobs.add(job));
        await sftp.downloadFile(
          child.fullPath,
          File('${local.path}/${child.name}'),
          onProgress: (done, total) => job.done = done,
        );
      }
    }
  }

  void _entryMenu(BuildContext context, SftpEntry e, Offset pos) {
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx + 1, pos.dy + 1),
      items: [
        if (e.name != '..')
          const PopupMenuItem(value: 'download', child: Text('下载…')),
        if (!e.isDirectory && e.name != '..')
          const PopupMenuItem(value: 'edit', child: Text('编辑')),
        const PopupMenuItem(value: 'upload', child: Text('上传文件…')),
        if (e.name != '..') ...[
          const PopupMenuItem(value: 'rename', child: Text('重命名…')),
          if (e.isDirectory)
            const PopupMenuItem(value: 'mkdir', child: Text('新建文件夹…')),
          const PopupMenuItem(value: 'chmod', child: Text('修改权限…')),
          const PopupMenuItem(value: 'delete', child: Text('删除')),
        ],
      ],
    ).then((v) async {
      if (v == null || !context.mounted) return;
      final sftp = _sftp;
      if (sftp == null) return;
      switch (v) {
        case 'download':
          if (e.isDirectory) {
            final dir = await getDirectoryPath(confirmButtonText: '保存到此处');
            if (dir == null) return;
            await _downloadTree(e, Directory('$dir/${e.name}'));
            _load(_path);
          } else {
            await _download(e);
          }
        case 'edit':
          final sftpEdit = _sftp;
          if (sftpEdit != null && context.mounted) {
            await showRemoteEditor(context, sftp: sftpEdit, path: e.fullPath);
          }
        case 'upload':
          await _upload();
        case 'rename':
          final name = await showPromptDialog(context,
              title: '重命名', initialValue: e.name);
          if (name != null && name.isNotEmpty && name != e.name) {
            await sftp.rename(e.fullPath, '$_path/$name');
            _load(_path);
          }
        case 'mkdir':
          final name =
              await showPromptDialog(context, title: '新建文件夹名称');
          if (name != null && name.isNotEmpty) {
            await sftp.mkdir('$_path/$name');
            _load(_path);
          }
        case 'chmod':
          final mode = await showPromptDialog(
            context,
            title: '权限 (八进制，如 644)',
            initialValue: (e.modeValue & 0x1FF).toRadixString(8),
          );
          final v = int.tryParse(mode ?? '', radix: 8);
          if (v != null) {
            await sftp.chmod(e.fullPath, v);
            _load(_path);
          }
        case 'delete':
          final ok = await showConfirmDialog(
            context,
            title: '删除',
            message: '确定删除 "${e.name}" 吗？',
          );
          if (ok) {
            if (e.isDirectory) {
              await sftp.removeTree(e.fullPath);
            } else {
              await sftp.deleteFile(e.fullPath);
            }
            _load(_path);
          }
      }
    });
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({
    required this.entry,
    required this.onTap,
    required this.onMenu,
  });

  final SftpEntry entry;
  final VoidCallback onTap;
  final void Function(Offset) onMenu;

  IconData get _icon {
    if (entry.isDirectory || entry.name == '..') {
      return Icons.folder_outlined;
    }
    final n = entry.name.toLowerCase();
    if (n.endsWith('.sh') || n.endsWith('.py') || n.endsWith('.js')) {
      return Icons.code;
    }
    if (n.endsWith('.tar') || n.endsWith('.gz') || n.endsWith('.zip') ||
        n.endsWith('.xz') || n.endsWith('.7z')) {
      return Icons.folder_zip_outlined;
    }
    if (n.endsWith('.png') || n.endsWith('.jpg') || n.endsWith('.svg')) {
      return Icons.image_outlined;
    }
    return Icons.description_outlined;
  }

  String get _size {
    if (entry.isDirectory || entry.name == '..') return '';
    const units = ['B', 'K', 'M', 'G', 'T'];
    var v = entry.size.toDouble();
    var u = 0;
    while (v >= 1024 && u < units.length - 1) {
      v /= 1024;
      u++;
    }
    return u == 0 ? '${v.toInt()}B' : '${v.toStringAsFixed(1)}${units[u]}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onSecondaryTapUp: (d) => onMenu(d.globalPosition),
      child: ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: const EdgeInsets.only(left: 10, right: 8),
      leading: Icon(_icon,
          size: 17,
          color: entry.isDirectory ? scheme.primary : scheme.onSurfaceVariant),
      title: Text(entry.name,
          style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${entry.modeString}  $_size',
        style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
      ),
      onTap: onTap,
      ),
    );
  }
}

class _JobBar extends StatelessWidget {
  const _JobBar({required this.job});

  final _TransferJob job;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final progress = job.total == 0 ? 1.0 : job.done / job.total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(job.name,
                  style: TextStyle(
                      fontSize: 10.5,
                      color: job.error != null
                          ? scheme.error
                          : scheme.onSurfaceVariant),
                  overflow: TextOverflow.ellipsis),
            ),
            Text(
              job.error != null
                  ? '失败'
                  : job.finished
                      ? '完成'
                      : '${(progress * 100).toStringAsFixed(0)}%',
              style: TextStyle(fontSize: 10, color: scheme.outline),
            ),
          ],
        ),
        SizedBox(
          height: 3,
          child: LinearProgressIndicator(
            value: job.error != null ? null : progress,
            minHeight: 3,
          ),
        ),
      ],
    );
  }
}

class _ErrorRetry extends StatelessWidget {
  const _ErrorRetry({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(error,
                style: const TextStyle(fontSize: 11),
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}
