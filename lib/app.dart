import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'state/app_state.dart';
import 'ui/main_shell.dart';
import 'ui/theme/app_theme.dart';

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
      theme: jtermTheme(dark: false, seed: seed),
      darkTheme: jtermTheme(dark: true, seed: seed),
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
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surface,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(Icons.terminal_rounded, color: scheme.primary, size: 28),
            ),
            const SizedBox(height: 16),
            Text(app.initError ?? '正在启动 JTerm…',
                style: TextStyle(color: scheme.onSurfaceVariant)),
            if (app.initError == null) ...[
              const SizedBox(height: 16),
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
