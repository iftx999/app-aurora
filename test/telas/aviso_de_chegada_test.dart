import 'package:aurora_campo/app/dependencias.dart';
import 'package:aurora_campo/app/tema.dart';
import 'package:aurora_campo/autenticacao/cofre.dart';
import 'package:aurora_campo/dados/api/erros.dart';
import 'package:aurora_campo/dados/local/arquivos_de_foto.dart';
import 'package:aurora_campo/dados/local/armazem_do_dia.dart';
import 'package:aurora_campo/telas/inicio/inicio_tela.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../apoio.dart';

/// "Estou chegando" (ADR 0052): só em OS programada de imóvel com celular; o número nunca vem para o app.
void main() {
  late ApiFalsa api;

  setUp(() {
    final ordens = [ordemJson('a', sequencia: 1, avisoDeChegada: true), ordemJson('b', sequencia: 2)];
    api = ApiFalsa(equipes: equipesDeTeste)..respostasDoPacote.add(pacoteJson(ordens: ordens));
  });

  Widget app({Brightness brilho = Brightness.light}) => ProviderScope(
    overrides: [
      apiCampoProvider.overrideWithValue(api),
      armazemProvider.overrideWithValue(
        ArmazemEmMemoria()
          ..pacote = (
            pacote: pacoteJson(
              ordens: [ordemJson('a', sequencia: 1, avisoDeChegada: true), ordemJson('b', sequencia: 2)],
            ),
            baixadoEm: agoraDosTestes,
          ),
      ),
      arquivosDeFotoProvider.overrideWithValue(ArquivosEmMemoria()),
      localizacaoProvider.overrideWithValue(GpsFalso()),
      fonteDePosicoesProvider.overrideWithValue(PosicoesFalsas()),
      aparelhoProvider.overrideWithValue(AparelhoFalso()),
      relogioProvider.overrideWithValue(() => agoraDosTestes),
      cofreProvider.overrideWithValue(CofreEmMemoria()),
    ],
    child: MaterialApp(theme: temaAurora(brilho), home: const InicioTela()),
  );

  Future<void> abrirAPrimeira(WidgetTester tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Ver OS'));
    await tester.pumpAndSettle();
  }

  Future<void> avisar(WidgetTester tester, String minutos) async {
    await tester.ensureVisible(find.text('Estou chegando'));
    await tester.tap(find.text('Estou chegando'));
    await tester.pumpAndSettle();
    expect(find.text('Avisar o morador'), findsOneWidget);
    await tester.tap(find.text(minutos));
    await tester.pumpAndSettle();
  }

  testWidgets('avisa o morador e mostra que já avisou', (tester) async {
    await abrirAPrimeira(tester);
    await avisar(tester, '10 minutos');
    expect(api.avisosDeChegada.single, (os: 'a', minutos: 10));
    expect(find.text('Morador avisado: chegada em cerca de 10 min.'), findsOneWidget);
    expect(find.text('Estou chegando'), findsNothing);
    expect(find.textContaining('Morador avisado às'), findsOneWidget);
  });

  testWidgets('sem provedor de SMS, sem sinal ou já avisado: a mensagem explica', (tester) async {
    api.situacaoDoAviso = 'REGISTRADO';
    await abrirAPrimeira(tester);
    api.semSinal = true;
    await avisar(tester, '5 minutos');
    expect(find.text('Sem sinal: o aviso não foi enviado. Tente quando houver sinal.'), findsOneWidget);
    expect(find.text('Estou chegando'), findsOneWidget);

    api.semSinal = false;
    api.erroNoAviso = const ErroDaApi(409, 'O morador já foi avisado às 08:40.');
    await avisar(tester, '5 minutos');
    expect(find.text('O morador já foi avisado às 08:40.'), findsOneWidget);

    api.erroNoAviso = null;
    await avisar(tester, '5 minutos');
    expect(find.text('Aviso registrado. O envio de SMS ainda não está ligado na sua empresa.'), findsOneWidget);
  });

  testWidgets('OS sem celular do morador não mostra o botão', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel(RegExp(r'^Parada 2,')));
    await tester.pumpAndSettle();
    expect(find.text('Estou chegando'), findsNothing);
  });

  for (final brilho in Brightness.values) {
    testWidgets('botão e escolha do tempo passam nas diretrizes de acessibilidade (${brilho.name})', (tester) async {
      final semantica = tester.ensureSemantics();
      await tester.pumpWidget(app(brilho: brilho));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Ver OS'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Estou chegando'));
      await tester.pumpAndSettle();
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await tester.tap(find.text('Estou chegando'));
      await tester.pumpAndSettle();
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      semantica.dispose();
    });
  }
}
