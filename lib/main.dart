import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await windowManager.ensureInitialized();
  const options = WindowOptions(
    title: 'JTerm',
    minimumSize: Size(960, 600),
    size: Size(1400, 900),
    center: true,
    titleBarStyle: TitleBarStyle.normal,
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await _setWindowIcon();
    await windowManager.show();
    await windowManager.focus();
  });

  final appState = AppState();
  // Init in the background; the shell shows a loader until it finishes.
  // ignore: discarded_futures
  appState.init();

  runApp(
    ChangeNotifierProvider.value(
      value: appState,
      child: const JTermApp(),
    ),
  );
}

/// Prefer the installed hicolor icon, then the copy shipped beside the binary.
Future<void> _setWindowIcon() async {
  final beside = '${File(Platform.resolvedExecutable).parent.path}/jterm.png';
  const installed = '/usr/share/icons/hicolor/256x256/apps/dev.jterm.jterm.png';
  for (final path in [beside, installed]) {
    if (File(path).existsSync()) {
      await windowManager.setIcon(path);
      return;
    }
  }
}
