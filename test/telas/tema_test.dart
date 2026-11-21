import 'package:aurora_campo/app/dependencias.dart';
import 'package:aurora_campo/app/tema.dart';
import 'package:aurora_campo/app/tema_do_dia.dart';
import 'package:aurora_campo/autenticacao/cofre.dart';
import 'package:aurora_campo/dados/local/arquivos_de_foto.dart';
import 'package:aurora_campo/dados/local/armazem_do_dia.dart';
import 'package:aurora_campo/telas/inicio/inicio_tela.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../apoio.dart';

void main() {
  testWidgets('o menu escolhe o tema da tela e guarda a escolha', (tester) async {
    final cofre = CofreEmMemoria();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiCampoProvider.overrideWithValue(ApiFalsa(equipes: equipesDeTeste)..respostasDoPacote.add(pacoteJson())),
          armazemProvider.overrideWithValue(
            ArmazemEmMemoria()..pacote = (pacote: pacoteJson(), baixadoEm: agoraDosTestes),
          ),
          arquivosDeFotoProvider.overrideWithValue(ArquivosEmMemoria()),
          localizacaoProvider.overrideWithValue(GpsFalso()),
          fonteDePosicoesProvider.overrideWithValue(PosicoesFalsas()),
          aparelhoProvider.overrideWithValue(AparelhoFalso()),
          relogioProvider.overrideWithValue(() => agoraDosTestes),
          cofreProvider.overrideWithValue(cofre),
        ],
        child: Consumer(
          builder: (_, ref, _) => MaterialApp(
            theme: temaAurora(Brightness.light),
            darkTheme: temaAurora(Brightness.dark),
            themeMode: ref.watch(temaDoDiaProvider).modo,
            home: const InicioTela(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // 9h: automático e de dia.
    expect(Theme.of(tester.element(find.byType(Scaffold).first)).brightness, Brightness.light);

    await tester.tap(find.byTooltip('Mais opções'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tema da tela'));
    await tester.pumpAndSettle();
    expect(find.text('Pelo nascer e pôr do sol onde a equipe trabalha'), findsOneWidget);
    await tester.tap(find.text('Sempre escuro'));
    await tester.pumpAndSettle();

    expect(Theme.of(tester.element(find.byType(Scaffold).first)).brightness, Brightness.dark);
    expect(await cofre.ler(ControleDoTema.chavePreferencia), 'escuro');
  });
}
