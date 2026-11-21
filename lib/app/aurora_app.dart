import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'rotas.dart';
import 'tema.dart';
import 'tema_do_dia.dart';

class AuroraApp extends ConsumerWidget {
  const AuroraApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Aurora Campo',
      debugShowCheckedModeBanner: false,
      theme: temaAurora(Brightness.light),
      darkTheme: temaAurora(Brightness.dark),
      // Modo noturno: escuro entre o pôr e o nascer do sol, ou a escolha do agente no menu.
      themeMode: ref.watch(temaDoDiaProvider).modo,
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: ref.watch(rotasProvider),
    );
  }
}
