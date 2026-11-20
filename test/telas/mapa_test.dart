import 'package:aurora_campo/app/dependencias.dart';
import 'package:aurora_campo/app/tema.dart';
import 'package:aurora_campo/autenticacao/cofre.dart';
import 'package:aurora_campo/dados/local/arquivos_de_foto.dart';
import 'package:aurora_campo/dados/local/armazem_do_dia.dart';
import 'package:aurora_campo/nucleo/configuracao.dart';
import 'package:aurora_campo/telas/inicio/inicio_tela.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../apoio.dart';

void main() {
  // Sem tiles nos testes (não há rede): só a rota, as paradas e a atribuição.
  final configuracao = Configuracao(
    api: Uri.parse('http://api'),
    identidade: Uri.parse('http://id'),
    mapa: const FundoDoMapa(tiles: '', atribuicao: '© Mapa de teste'),
  );

  Widget app(ApiFalsa api, ArmazemEmMemoria armazem, {Brightness brilho = Brightness.light}) => ProviderScope(
    overrides: [
      configuracaoProvider.overrideWithValue(configuracao),
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

  (ApiFalsa, ArmazemEmMemoria) preparar({bool pelaMalha = true}) {
    final api = ApiFalsa(equipes: equipesDeTeste)
      ..respostasDoPacote.add(pacoteJson())
      ..rotaPublicada = rotaJson(pelaMalha: pelaMalha);
    final armazem = ArmazemEmMemoria()..pacote = (pacote: pacoteJson(), baixadoEm: agoraDosTestes);
    return (api, armazem);
  }

  Future<void> abrirOMapa(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Mapa da rota'));
    await tester.pumpAndSettle();
  }

  testWidgets('o mapa mostra o resumo da rota e as paradas; tocar abre a OS', (tester) async {
    final (api, armazem) = preparar();
    await tester.pumpWidget(app(api, armazem));
    await tester.pumpAndSettle();
    await abrirOMapa(tester);

    expect(find.text('Mapa da rota'), findsOneWidget);
    expect(find.text('12,4 km · 38 min de deslocamento · fim previsto 15:40'), findsOneWidget);
    expect(find.text('Calculada da sua posição no início · pelas ruas · estimativa'), findsOneWidget);
    expect(find.bySemanticsLabel('Você'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^Parada 2, Religação')), findsOneWidget);

    await tester.tap(find.bySemanticsLabel(RegExp(r'^Parada 2, Religação')));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Iniciar OS'), findsOneWidget);
  });

  testWidgets('em linha reta e sem rota publicada, o resumo avisa', (tester) async {
    final (api, armazem) = preparar(pelaMalha: false);
    await tester.pumpWidget(app(api, armazem));
    await tester.pumpAndSettle();
    await abrirOMapa(tester);
    expect(find.textContaining('em linha reta · estimativa'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    api.rotaPublicada = null;
    await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();
    await abrirOMapa(tester);
    expect(find.text('Rota ainda não calculada: a lista segue a ordem da programação.'), findsOneWidget);
  });

  for (final brilho in Brightness.values) {
    testWidgets('o mapa passa nas diretrizes de acessibilidade (${brilho.name})', (tester) async {
      final semantica = tester.ensureSemantics();
      final (api, armazem) = preparar();
      await tester.pumpWidget(app(api, armazem, brilho: brilho));
      await tester.pumpAndSettle();
      await abrirOMapa(tester);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      semantica.dispose();
    });
  }
}
