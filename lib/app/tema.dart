import 'package:flutter/material.dart';

/// Cores da Aurora (doc 07; os mesmos tokens do front em src/styles/_tokens.scss).
@immutable
class CoresAurora extends ThemeExtension<CoresAurora> {
  const CoresAurora({
    required this.fundo,
    required this.superficie,
    required this.linha,
    required this.texto,
    required this.textoSecundario,
    required this.textoTerciario,
    required this.destaque,
    required this.sobreDestaque,
    required this.ok,
    required this.atencao,
    required this.perigo,
    required this.neutro,
  });

  static const escuro = CoresAurora(
    fundo: Color(0xFF0B1A1F),
    superficie: Color(0xFF12212A),
    linha: Color(0xFF1C2E36),
    texto: Color(0xFFE8F0EE),
    textoSecundario: Color(0xFFB4C1C3),
    textoTerciario: Color(0xFF7A8D93),
    destaque: Color(0xFF4AD7BC),
    sobreDestaque: Color(0xFF04201B),
    ok: Color(0xFF3DE693),
    atencao: Color(0xFFECC32A),
    perigo: Color(0xFFEC8087),
    neutro: Color(0xFF86929E),
  );

  static const claro = CoresAurora(
    fundo: Color(0xFFF4F8F7),
    superficie: Color(0xFFFFFFFF),
    linha: Color(0xFFD3E0DD),
    texto: Color(0xFF0B1A1F),
    textoSecundario: Color(0xFF3D5359),
    textoTerciario: Color(0xFF5B6F74),
    destaque: Color(0xFF0A6B5B),
    sobreDestaque: Color(0xFFFFFFFF),
    ok: Color(0xFF176038),
    atencao: Color(0xFF6A5813),
    perigo: Color(0xFF8B3A3F),
    neutro: Color(0xFF58636E),
  );

  final Color fundo;
  final Color superficie;
  final Color linha;
  final Color texto;
  final Color textoSecundario;
  final Color textoTerciario;
  final Color destaque;
  final Color sobreDestaque;
  final Color ok;
  final Color atencao;
  final Color perigo;
  final Color neutro;

  @override
  CoresAurora copyWith() => this;

  @override
  CoresAurora lerp(CoresAurora? other, double t) => t < 0.5 || other == null ? this : other;
}

extension CoresDoContexto on BuildContext {
  CoresAurora get cores => Theme.of(this).extension<CoresAurora>()!;
}

/// Material 3 com as cores da Aurora; alvos de toque de 56 dp e texto maior (uso ao sol e com luva, 10.9.1).
ThemeData temaAurora(Brightness brilho) {
  final c = brilho == Brightness.dark ? CoresAurora.escuro : CoresAurora.claro;
  final esquema = ColorScheme(
    brightness: brilho,
    primary: c.destaque,
    onPrimary: c.sobreDestaque,
    secondary: c.destaque,
    onSecondary: c.sobreDestaque,
    error: c.perigo,
    onError: brilho == Brightness.dark ? c.fundo : Colors.white,
    surface: c.superficie,
    onSurface: c.texto,
    onSurfaceVariant: c.textoSecundario,
    outline: c.linha,
    surfaceContainerLowest: c.fundo,
    surfaceContainerLow: c.fundo,
    surfaceContainer: c.superficie,
  );
  final base = ThemeData(colorScheme: esquema, useMaterial3: true, brightness: brilho);
  final alvo = const Size.fromHeight(56);
  final forma = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
  return base.copyWith(
    scaffoldBackgroundColor: c.fundo,
    extensions: [c],
    textTheme: base.textTheme.apply(bodyColor: c.texto, displayColor: c.texto).copyWith(
      bodyLarge: base.textTheme.bodyLarge?.copyWith(fontSize: 17, color: c.texto),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(fontSize: 15, color: c.texto),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: alvo,
        shape: forma,
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: alvo,
        shape: forma,
        side: BorderSide(color: c.linha, width: 1.5),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: const Size(48, 48), textStyle: const TextStyle(fontSize: 15)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
    ),
  );
}
