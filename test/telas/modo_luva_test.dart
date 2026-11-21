import 'package:aurora_campo/app/dependencias.dart';
import 'package:aurora_campo/app/modo_luva.dart';
import 'package:aurora_campo/app/tema.dart';
import 'package:aurora_campo/autenticacao/cofre.dart';
import 'package:aurora_campo/dados/local/arquivos_de_foto.dart';
import 'package:aurora_campo/dados/local/armazem_do_dia.dart';
import 'package:aurora_campo/dados/modelos/evento.dart';
import 'package:aurora_campo/telas/inicio/inicio_tela.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../apoio.dart';

/// Modo luva (ADR 0051): botões maiores e as ações da OS por toque longo.
void main() {
  late ApiFalsa api;
  late ArmazemEmMemoria armazem;
  late CofreEmMemoria cofre;

  setUp(() {
    api = ApiFalsa(equipes: equipesDeTeste)
      ..respostasDoPacote.add(pacoteJson(diferenca: true, ordens: const [], ids: const ['a']));
    armazem = ArmazemEmMemoria()
      ..pacote = (pacote: pacoteJson(ordens: [ordemJson('a', sequencia: 1)]), baixadoEm: agoraDosTestes);
    cofre = CofreEmMemoria();
  });

  Widget app({Brightness brilho = Brightness.light}) => ProviderScope(
    overrides: [
      apiCampoProvider.overrideWithValue(api),
      armazemProvider.overrideWithValue(armazem),
      arquivosDeFotoProvider.overrideWithValue(ArquivosEmMemoria()),
      localizacaoProvider.overrideWithValue(GpsFalso()),
      fonteDePosicoesProvider.overrideWithValue(PosicoesFalsas()),
      aparelhoProvider.overrideWithValue(AparelhoFalso()),
      relogioProvider.overrideWithValue(() => agoraDosTestes),
      cofreProvider.overrideWithValue(cofre),
    ],
    child: Consumer(
      builder: (_, ref, _) => MaterialApp(
        theme: temaAurora(brilho, luva: ref.watch(modoLuvaProvider)),
        home: const InicioTela(),
      ),
    ),
  );

  Future<void> ligarPeloMenu(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Mais opções'));
    await tester.pumpAndSettle();
    await tester.tap(find.ancestor(of: find.text('Modo luva'), matching: find.byType(ListTile)));
    await tester.pumpAndSettle();
  }

  testWidgets('ligado no menu: botões maiores; toque rápido só avisa, segurar inicia a OS', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    final normal = tester.getSize(find.widgetWithText(FilledButton, 'Navegar')).height;
    await ligarPeloMenu(tester);
    expect(await cofre.ler(ControleDoModoLuva.chave), 'sim');
    expect(tester.getSize(find.widgetWithText(FilledButton, 'Navegar')).height, greaterThan(normal));

    api.semSinal = true;
    await tester.tap(find.widgetWithText(OutlinedButton, 'Ver OS'));
    await tester.pumpAndSettle();
    final iniciar = find.text('Segure para iniciar OS');
    expect(iniciar, findsOneWidget);

    await tester.tap(iniciar);
    await tester.pumpAndSettle();
    expect(find.text('Modo luva: segure o botão até a barra encher.'), findsOneWidget);
    expect(armazem.fila, isEmpty);
    // O aviso some sozinho.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    final dedo = await tester.startGesture(tester.getCenter(iniciar));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await dedo.up();
    await tester.pumpAndSettle();
    expect(armazem.fila.single.evento.acao, AcaoDeCampo.iniciar);
    expect(find.text('Em execução'), findsWidgets);
    expect(find.text('Modo luva: segure o botão até a barra encher.'), findsNothing);
  });

  testWidgets('desligado (padrão), o toque normal inicia a OS', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    api.semSinal = true;
    await tester.tap(find.widgetWithText(OutlinedButton, 'Ver OS'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Iniciar OS'));
    await tester.pumpAndSettle();
    expect(armazem.fila.single.evento.acao, AcaoDeCampo.iniciar);
  });

  for (final brilho in Brightness.values) {
    testWidgets('modo luva passa nas diretrizes de acessibilidade (${brilho.name})', (tester) async {
      final semantica = tester.ensureSemantics();
      await cofre.escrever(ControleDoModoLuva.chave, 'sim');
      await tester.pumpWidget(app(brilho: brilho));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Ver OS'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Iniciar OS'), findsOneWidget);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      semantica.dispose();
    });
  }
}
