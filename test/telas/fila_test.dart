import 'package:aurora_campo/app/dependencias.dart';
import 'package:aurora_campo/app/tema.dart';
import 'package:aurora_campo/autenticacao/cofre.dart';
import 'package:aurora_campo/dados/api/api_campo.dart';
import 'package:aurora_campo/dados/local/arquivos_de_foto.dart';
import 'package:aurora_campo/dados/local/armazem_do_dia.dart';
import 'package:aurora_campo/dados/modelos/evento.dart';
import 'package:aurora_campo/telas/inicio/inicio_tela.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../apoio.dart';

void main() {
  late PosicoesFalsas fonte;

  Widget app(ApiFalsa api, ArmazemEmMemoria armazem, {Brightness brilho = Brightness.light}) => ProviderScope(
    overrides: [
      apiCampoProvider.overrideWithValue(api),
      armazemProvider.overrideWithValue(armazem),
      arquivosDeFotoProvider.overrideWithValue(ArquivosEmMemoria()),
      localizacaoProvider.overrideWithValue(GpsFalso()),
      fonteDePosicoesProvider.overrideWithValue(fonte),
      aparelhoProvider.overrideWithValue(AparelhoFalso()),
      relogioProvider.overrideWithValue(() => agoraDosTestes),
      cofreProvider.overrideWithValue(CofreEmMemoria()),
    ],
    child: MaterialApp(theme: temaAurora(brilho), home: const InicioTela()),
  );

  /// Em jornada, sem sinal, com uma ação recusada de ontem e outra na fila.
  Future<(ApiFalsa, ArmazemEmMemoria)> preparar() async {
    fonte = PosicoesFalsas();
    final api = ApiFalsa(equipes: equipesDeTeste)
      ..respostasDoPacote.add(pacoteJson())
      ..semSinal = true;
    final armazem = ArmazemEmMemoria()..pacote = (pacote: pacoteJson(), baixadoEm: agoraDosTestes);
    await armazem.registrarEvento(eventoDeTeste('c1', os: 'c'));
    await armazem.marcarRecusado('c1', 'A OS foi cancelada pelo programador.', agoraDosTestes);
    await armazem.registrarEvento(eventoDeTeste('a1'));
    await armazem.guardarPosicao(AmostraDePosicao(agoraDosTestes, const Posicao(-22.56, -47.40)));
    return (api, armazem);
  }

  testWidgets('a fila mostra pendências, respostas e a localização; "Enviar agora" envia tudo', (tester) async {
    final (api, armazem) = await preparar();
    await tester.pumpWidget(app(api, armazem));
    await tester.pumpAndSettle();
    expect(find.textContaining('Localização registrada'), findsOneWidget);

    await tester.tap(find.textContaining('1 ação pendente'));
    await tester.pumpAndSettle();
    expect(find.text('Fila de envio'), findsOneWidget);
    expect(find.text('Ações pendentes'), findsOneWidget);
    expect(find.text('Posições pendentes'), findsOneWidget);
    expect(find.textContaining('Uma posição a cada 2 min ou 100 m'), findsOneWidget);
    expect(find.text('Recusada'), findsOneWidget);
    expect(find.textContaining('A OS foi cancelada pelo programador.'), findsOneWidget);
    expect(find.textContaining('Pendente'), findsOneWidget);

    api.semSinal = false;
    await tester.tap(find.widgetWithText(FilledButton, 'Enviar agora'));
    await tester.pumpAndSettle();
    expect(api.lotes.single.single.id, 'a1');
    expect(api.lotesDePosicoes.single, hasLength(1));
    expect(find.text('Recebida'), findsOneWidget);
    expect(armazem.fila.firstWhere((e) => e.evento.id == 'a1').situacao, SituacaoDoEnvio.aplicado);
  });

  for (final brilho in Brightness.values) {
    testWidgets('a fila passa nas diretrizes de acessibilidade (${brilho.name})', (tester) async {
      final semantica = tester.ensureSemantics();
      final (api, armazem) = await preparar();
      await tester.pumpWidget(app(api, armazem, brilho: brilho));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('1 ação pendente'));
      await tester.pumpAndSettle();
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      semantica.dispose();
    });
  }
}
