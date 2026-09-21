import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'state/app_state.dart';
import 'ui/main_shell.dart';

class JTermApp extends StatelessWidget {
  const JTermApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppState>().initialized
        ? context.watch<AppState>().settings
        : null;
    final seed = Color(settings?.themeSeed ?? 0xFF0F766E);

    return MaterialApp(
      title: 'JTerm',
      debugShowCheckedModeBanner: false,
      themeMode: (settings?.darkMode ?? true) ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seed),
        useMaterial3: true,
        fontFamily: 'monospace',
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        fontFamily: 'monospace',
      ),
      home: settings == null
          ? const _BootScreen()
          : ChangeNotifierProvider.value(
              value: settings,
              child: const MainShell(),
            ),
    );
  }
}

class _BootScreen extends StatelessWidget {
  const _BootScreen();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Material(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(app.initError ?? '正在初始化 JTerm…'),
          ],
        ),
      ),
    );
  }
}
