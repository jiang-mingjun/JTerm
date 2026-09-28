/// Named terminal palettes. Each entry is a full xterm [TerminalTheme].
library;

import 'package:flutter/painting.dart';
import 'package:xterm/xterm.dart';

class TerminalThemeChoice {
  const TerminalThemeChoice(this.id, this.label, this.theme);

  final String id;
  final String label;
  final TerminalTheme theme;
}

TerminalTheme _theme({
  required int bg,
  required int fg,
  required int cursor,
  required List<int> ansi,
}) {
  return TerminalTheme(
    cursor: Color(cursor),
    selection: const Color(0xAA3D4F6F),
    foreground: Color(fg),
    background: Color(bg),
    black: Color(ansi[0]),
    red: Color(ansi[1]),
    green: Color(ansi[2]),
    yellow: Color(ansi[3]),
    blue: Color(ansi[4]),
    magenta: Color(ansi[5]),
    cyan: Color(ansi[6]),
    white: Color(ansi[7]),
    brightBlack: Color(ansi[8]),
    brightRed: Color(ansi[9]),
    brightGreen: Color(ansi[10]),
    brightYellow: Color(ansi[11]),
    brightBlue: Color(ansi[12]),
    brightMagenta: Color(ansi[13]),
    brightCyan: Color(ansi[14]),
    brightWhite: Color(ansi[15]),
    searchHitBackground: const Color(0xFFFFFF2B),
    searchHitBackgroundCurrent: const Color(0xFF31FF26),
    searchHitForeground: const Color(0xFF000000),
  );
}

final terminalThemeChoices = <TerminalThemeChoice>[
  TerminalThemeChoice('jterm-dark', 'JTerm Dark', TerminalThemes.defaultTheme),
  TerminalThemeChoice(
    'dracula',
    'Dracula',
    _theme(
      bg: 0xFF282A36,
      fg: 0xFFF8F8F2,
      cursor: 0xFFF8F8F2,
      ansi: const [
        0xFF21222C, 0xFFFF5555, 0xFF50FA7B, 0xFFF1FA8C,
        0xFFBD93F9, 0xFFFF79C6, 0xFF8BE9FD, 0xFFF8F8F2,
        0xFF6272A4, 0xFFFF6E6E, 0xFF69FF94, 0xFFFFFFA5,
        0xFFD6ACFF, 0xFFFF92DF, 0xFFA4FFFF, 0xFFFFFFFF,
      ],
    ),
  ),
  TerminalThemeChoice(
    'nord',
    'Nord',
    _theme(
      bg: 0xFF2E3440,
      fg: 0xFFD8DEE9,
      cursor: 0xFFD8DEE9,
      ansi: const [
        0xFF3B4252, 0xFFBF616A, 0xFFA3BE8C, 0xFFEBCB8B,
        0xFF81A1C1, 0xFFB48EAD, 0xFF88C0D0, 0xFFE5E9F0,
        0xFF4C566A, 0xFFBF616A, 0xFFA3BE8C, 0xFFEBCB8B,
        0xFF81A1C1, 0xFFB48EAD, 0xFF8FBCBB, 0xFFECEFF4,
      ],
    ),
  ),
  TerminalThemeChoice(
    'solarized-dark',
    'Solarized Dark',
    _theme(
      bg: 0xFF002B36,
      fg: 0xFF839496,
      cursor: 0xFF839496,
      ansi: const [
        0xFF073642, 0xFFDC322F, 0xFF859900, 0xFFB58900,
        0xFF268BD2, 0xFFD33682, 0xFF2AA198, 0xFFEEE8D5,
        0xFF002B36, 0xFFCB4B16, 0xFF586E75, 0xFF657B83,
        0xFF839496, 0xFF6C71C4, 0xFF93A1A1, 0xFFFDF6E3,
      ],
    ),
  ),
  TerminalThemeChoice(
    'monokai',
    'Monokai',
    _theme(
      bg: 0xFF272822,
      fg: 0xFFF8F8F2,
      cursor: 0xFFF8F8F0,
      ansi: const [
        0xFF272822, 0xFFF92672, 0xFFA6E22E, 0xFFF4BF75,
        0xFF66D9EF, 0xFFAE81FF, 0xFFA1EFE4, 0xFFF8F8F2,
        0xFF75715E, 0xFFF92672, 0xFFA6E22E, 0xFFF4BF75,
        0xFF66D9EF, 0xFFAE81FF, 0xFFA1EFE4, 0xFFF9F8F5,
      ],
    ),
  ),
  TerminalThemeChoice(
    'light',
    'Light',
    _theme(
      bg: 0xFFF7F7F5,
      fg: 0xFF1F2328,
      cursor: 0xFF1F2328,
      ansi: const [
        0xFF24292F, 0xFFCF222E, 0xFF116329, 0xFF9A6700,
        0xFF0969DA, 0xFF8250DF, 0xFF1B7C83, 0xFF6E7781,
        0xFF57606A, 0xFFFA4549, 0xFF1A7F37, 0xFFBF8700,
        0xFF218BFF, 0xFFA475F9, 0xFF3192AA, 0xFF8C959F,
      ],
    ),
  ),
];

TerminalTheme terminalThemeById(String id) {
  for (final choice in terminalThemeChoices) {
    if (choice.id == id) return choice.theme;
  }
  return TerminalThemes.defaultTheme;
}
