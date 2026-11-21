import 'package:aurora_campo/app/dependencias.dart';
import 'package:aurora_campo/app/tema.dart';
import 'package:aurora_campo/autenticacao/cofre.dart';
import 'package:aurora_campo/dados/local/arquivos_de_foto.dart';
import 'package:aurora_campo/dados/local/armazem_do_dia.dart';
import 'package:aurora_campo/telas/inicio/inicio_tela.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../apoio.dart';

/// J7 (ADR 0050): o aviso da nova ordem na tela Hoje e a tela de conferir e confirmar.
void main() {
  Widget app(ApiFalsa api, ArmazemEmMemoria armazem, {Brightness brilho = Brightness.light}) => ProviderScope(
    overrides: [
      apiCampoProvider.overrideWithValue(api),
      armazemProvider.overrideWithValue(armazem),
      arquivosDeFotoProvider.overrideWithValue(ArquivosEmMemoria()),
      localizacaoProvider.overrideWithValue(GpsFalso()),
      fonteDePosicoesProvider.overrideWithValue(PosicoesFalsas()),
      aparelhoProvider.overrideWithValue(AparelhoFalso()),
      relogioProvider.overrideWithValue(() => agoraDosTestes),
      cofreProvider.overrideWithValue(CofreEmMemoria()),
    ],
    child: MaterialApp(theme: temaAurora(brilho), home: const InicioTela()),
  );

  (ApiFalsa, ArmazemEmMemoria) preparar() {
    final api = ApiFalsa(equipes: equipesDeTeste)
      ..respostasDoPacote.add(
        pacoteJson(
          ordens: [
            ordemJson('a', sequencia: 2),
            ordemJson('b', sequencia: 3, servico: 'Vistoria de viabilidade'),
            ordemJson('c', sequencia: 1, servico: 'Desobstrução de ramal'),
          ],
        ),
      )
      ..rotaPublicada = rotaJson(
        id: 'r2',
        origem: 'REOTIMIZACAO',
        ordem: const ['c', 'a', 'b'],
        exigeConfirmacao: true,
      );
    final armazem = ArmazemEmMemoria()
      ..pacote = (
        pacote: pacoteJson(
          ordens: [
            ordemJson('a', sequencia: 2),
            ordemJson('b', sequencia: 1, servico: 'Vistoria de viabilidade'),
            ordemJson('c', sequencia: 3, servico: 'Desobstrução de ramal'),
          ],
        ),
        baixadoEm: agoraDosTestes,
      )
      ..rota = (rota: rotaJson(origem: 'PREVIA'), etag: '"r1"');
    return (api, armazem);
  }

  testWidgets('a Hoje avisa; conferir mostra o que mudou; confirmar troca a lista', (tester) async {
    final (api, armazem) = preparar();
    await tester.pumpWidget(app(api, armazem));
    await tester.pumpAndSettle();

    expect(find.text('Nova ordem das OS'), findsOneWidget);
    // Até confirmar, a próxima é a da ordem anterior (b, que aparece como parada 1).
    expect(find.text('Próxima · parada 1'), findsOneWidget);
    expect(find.widgetWithText(Card, 'Vistoria de viabilidade'), findsOneWidget);

    await tester.tap(find.text('Conferir e confirmar'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp(r'^Parada 1, Desobstrução de ramal, .*Subiu \(era a 3ª\)$')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^Parada 2, Religação, .*Mesma posição$')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^Parada 3, .*Desceu \(era a 1ª\)$')), findsOneWidget);

    await tester.tap(find.text('Confirmar nova ordem'));
    await tester.pumpAndSettle();
    expect(find.text('Nova ordem confirmada. O programador foi avisado.'), findsOneWidget);
    expect(find.text('Nova ordem das OS'), findsNothing);
    expect(find.widgetWithText(Card, 'Desobstrução de ramal'), findsOneWidget);
    expect(api.confirmacoesDeRota.single.id, 'r2');
  });

  testWidgets('"Agora não" mantém a ordem anterior e o aviso', (tester) async {
    final (api, armazem) = preparar();
    await tester.pumpWidget(app(api, armazem));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Conferir e confirmar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agora não'));
    await tester.pumpAndSettle();
    expect(find.text('Nova ordem das OS'), findsOneWidget);
    expect(api.confirmacoesDeRota, isEmpty);
  });

  for (final brilho in Brightness.values) {
    testWidgets('aviso e tela da nova ordem passam nas diretrizes de acessibilidade (${brilho.name})', (tester) async {
      final semantica = tester.ensureSemantics();
      final (api, armazem) = preparar();
      await tester.pumpWidget(app(api, armazem, brilho: brilho));
      await tester.pumpAndSettle();
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await tester.tap(find.text('Conferir e confirmar'));
      await tester.pumpAndSettle();
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      semantica.dispose();
    });
  }
}
