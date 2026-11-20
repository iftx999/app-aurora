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

  testWidgets('escolhe a equipe, inicia e vê a lista do dia na ordem da rota', (tester) async {
    final api = ApiFalsa(equipes: equipesDeTeste);
    await tester.pumpWidget(app(api, ArmazemEmMemoria()));
    await tester.pumpAndSettle();

    expect(find.text('Quarta, 18 de novembro'), findsOneWidget);
    expect(find.text('Com qual equipe você sai hoje?'), findsOneWidget);
    expect(find.text('3 OS hoje · 1 emergencial · Caminhão hidrojato'), findsOneWidget);

    // Duas equipes: nenhuma marcada até escolher.
    final iniciar = find.widgetWithText(FilledButton, 'Iniciar jornada');
    expect(tester.widget<FilledButton>(iniciar).onPressed, isNull);
    await tester.tap(find.text('Equipe Ligações Norte'));
    await tester.pump();
    await tester.tap(find.text('Equipe Rede Centro'));
    await tester.pump();
    await tester.tap(iniciar);
    await tester.pumpAndSettle();

    expect(api.inicios.single['equipeId'], equipeRede);
    expect(find.text('Hoje · 18 nov'), findsOneWidget);
    expect(find.text('Equipe Rede Centro · 3 OS'), findsOneWidget);
    // Próxima: a parada 2 (a 1 já foi encerrada).
    expect(find.text('Próxima · parada 2'), findsOneWidget);
    expect(find.text('Encerrada'), findsOneWidget);
    expect(find.text('Emergencial'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Navegar'), findsOneWidget);
  });

  testWidgets('encerrar a jornada pede confirmação e volta ao início', (tester) async {
    final api = ApiFalsa(equipes: equipesDeTeste)
      ..respostasDoPacote.add(pacoteJson(diferenca: true, ordens: const [], ids: const ['a', 'b', 'c']));
    final armazem = ArmazemEmMemoria()..pacote = (pacote: pacoteJson(), baixadoEm: agoraDosTestes);
    await tester.pumpWidget(app(api, armazem));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Mais opções'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Encerrar jornada'));
    await tester.pumpAndSettle();
    expect(find.text('Encerrar a jornada?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Encerrar'));
    await tester.pumpAndSettle();

    expect(api.encerramentos, 1);
    expect(find.text('Com qual equipe você sai hoje?'), findsOneWidget);
  });

  testWidgets('iniciar a OS sem sinal: a tela muda na hora e a fila mostra a pendência', (tester) async {
    final api = ApiFalsa(equipes: equipesDeTeste)..respostasDoPacote.add(pacoteJson());
    final armazem = ArmazemEmMemoria()..pacote = (pacote: pacoteJson(), baixadoEm: agoraDosTestes);
    await tester.pumpWidget(app(api, armazem));
    await tester.pumpAndSettle();
    expect(find.text('Tudo enviado'), findsOneWidget);

    api.semSinal = true;
    await tester.tap(find.widgetWithText(OutlinedButton, 'Ver OS'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Iniciar OS'));
    await tester.pumpAndSettle();
    expect(find.text('Em execução'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Encerrar OS'), findsOneWidget);
    expect(find.text('Início 09:00 · na fila'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('Em execução · parada 2'), findsOneWidget);
    expect(find.textContaining('1 ação pendente'), findsOneWidget);
    expect(armazem.fila.single.evento.acao.name, 'iniciar');

    api.semSinal = false;
    await tester.tap(find.text('Enviar agora'));
    await tester.pumpAndSettle();
    expect(api.lotes, hasLength(1));
    expect(find.textContaining('Tudo enviado · último envio'), findsOneWidget);
  });

  for (final brilho in Brightness.values) {
    testWidgets('a lista do dia passa nas diretrizes de acessibilidade (${brilho.name})', (tester) async {
      final semantica = tester.ensureSemantics();
      final api = ApiFalsa(equipes: equipesDeTeste)..respostasDoPacote.add(pacoteJson());
      final armazem = ArmazemEmMemoria()..pacote = (pacote: pacoteJson(), baixadoEm: agoraDosTestes);
      await tester.pumpWidget(app(api, armazem, brilho: brilho));
      await tester.pumpAndSettle();
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      semantica.dispose();
    });
  }
}
