import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/aurora_app.dart';
import 'app/dependencias.dart';
import 'dados/aparelho.dart';
import 'nucleo/configuracao.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Android Enterprise: endereços, empresa e mapa vindos do MDM valem sobre os da compilação. Mudanças no console
  // valem na próxima abertura do app.
  final gerenciada = await AparelhoAndroid.configuracaoGerenciada();
  runApp(
    ProviderScope(
      overrides: [configuracaoProvider.overrideWithValue(Configuracao.doAmbiente(gerenciada: gerenciada))],
      child: const AuroraApp(),
    ),
  );
}
