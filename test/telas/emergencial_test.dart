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

/// ADR 0051: o alerta da emergencial nova na tela Hoje.
void main() {
  Widget app({Brightness brilho = Brightness.light}) {
    final api = ApiFalsa(equipes: equipesDeTeste)
      ..respostasDoPacote.add(
        pacoteJson(
          ordens: [
            ordemJson('a', sequencia: 1),
            ordemJson('e', prioridade: 'EMERGENCIAL', servico: 'Desobstrução de rede', rua: 'R. Boa Morte'),
          ],
        ),
      );
    final armazem = ArmazemEmMemoria()
      ..pacote = (pacote: pacoteJson(ordens: [ordemJson('a', sequencia: 1)]), baixadoEm: agoraDosTestes)
      ..emergenciaisAvisadas = const [];
    return ProviderScope(
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
  }

  testWidgets('a emergencial nova aparece em destaque; "Ver OS" abre a OS e some o alerta', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('OS emergencial nova'), findsOneWidget);
    expect(find.textContaining('Desobstrução de rede · R. Boa Morte'), findsWidgets);

    await tester.tap(find.widgetWithText(FilledButton, 'Ver OS'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Iniciar OS'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('OS emergencial nova'), findsNothing);
  });

  for (final brilho in Brightness.values) {
    testWidgets('o alerta passa nas diretrizes de acessibilidade (${brilho.name})', (tester) async {
      final semantica = tester.ensureSemantics();
      await tester.pumpWidget(app(brilho: brilho));
      await tester.pumpAndSettle();
      expect(find.text('OS emergencial nova'), findsOneWidget);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      semantica.dispose();
    });
  }
}
