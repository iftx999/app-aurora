import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'rotas.dart';
import 'tema.dart';

class AuroraApp extends ConsumerWidget {
  const AuroraApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Aurora Campo',
      debugShowCheckedModeBanner: false,
      theme: temaAurora(Brightness.light),
      darkTheme: temaAurora(Brightness.dark),
      // Segue o celular (claro de dia, escuro à noite); a escolha manual fica para quando o cliente decidir (10.14).
      themeMode: ThemeMode.system,
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: ref.watch(rotasProvider),
    );
  }
}
