import 'package:aurora_campo/app/dependencias.dart';
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

/// Parâmetros como os da ligação nova de esgoto.
final parametrosDaLigacao = [
  {'chave': 'viavel', 'rotulo': 'Ligação viável', 'tipo': 'SIM_NAO', 'obrigatorio': true},
  {
    'chave': 'extensao',
    'rotulo': 'Extensão do ramal',
    'tipo': 'DECIMAL',
    'obrigatorio': true,
    'minimo': 0.5,
    'maximo': 100,
    'unidade': 'm',
    'condicaoChave': 'viavel',
    'condicaoValor': 'true',
  },
  {
    'chave': 'diametro',
    'rotulo': 'Diâmetro',
    'tipo': 'LISTA',
    'obrigatorio': true,
    'opcoes': ['100 mm', '150 mm'],
  },
  {'chave': 'fachada', 'rotulo': 'Foto da fachada', 'tipo': 'FOTO', 'obrigatorio': true, 'minimo': 1, 'maximo': 2},
];

void main() {
  late ApiFalsa api;
  late ArmazemEmMemoria armazem;
  late ArquivosEmMemoria arquivos;

  setUp(() {
    api = ApiFalsa(equipes: equipesDeTeste);
    final pacote = pacoteJson(
      ordens: [
        ordemJson('a', sequencia: 1, status: 'EM_EXECUCAO', servico: 'Ligação nova de esgoto', ultimaSequencia: 1),
        ordemJson('b', sequencia: 2),
      ],
      parametros: parametrosDaLigacao,
    );
    api.respostasDoPacote.add(pacoteJson(diferenca: true, ordens: const [], ids: const ['a', 'b']));
    armazem = ArmazemEmMemoria()..pacote = (pacote: pacote, baixadoEm: agoraDosTestes);
    arquivos = ArquivosEmMemoria();
  });

  Widget app({Brightness brilho = Brightness.light}) => ProviderScope(
    overrides: [
      apiCampoProvider.overrideWithValue(api),
      armazemProvider.overrideWithValue(armazem),
      arquivosDeFotoProvider.overrideWithValue(arquivos),
      cameraProvider.overrideWithValue(CameraFalsa()),
      localizacaoProvider.overrideWithValue(GpsFalso()),
      fonteDePosicoesProvider.overrideWithValue(PosicoesFalsas()),
      aparelhoProvider.overrideWithValue(AparelhoFalso()),
      relogioProvider.overrideWithValue(() => agoraDosTestes),
      cofreProvider.overrideWithValue(CofreEmMemoria()),
    ],
    child: MaterialApp(theme: temaAurora(brilho), home: const InicioTela()),
  );

  Future<void> abrirOs(WidgetTester tester, {String botao = 'Ver OS'}) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    api.semSinal = true; // tudo fica na fila: o que se vê é o celular
    await tester.tap(find.widgetWithText(OutlinedButton, botao));
    await tester.pumpAndSettle();
  }

  Future<void> tocar(WidgetTester tester, Finder alvo) async {
    await tester.ensureVisible(alvo);
    await tester.pumpAndSettle();
    await tester.tap(alvo);
  }

  Future<void> rolarAte(WidgetTester tester, Finder alvo, {bool paraCima = false}) =>
      tester.scrollUntilVisible(alvo, paraCima ? -200 : 200, scrollable: find.byType(Scrollable).first);

  testWidgets('paralisar exige o motivo, e "Outro" exige a observação', (tester) async {
    await abrirOs(tester);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Paralisar'));
    await tester.pumpAndSettle();
    expect(find.text('Paralisar OS ${1000 + 'a'.hashCode % 1000}'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Paralisar'));
    await tester.pump();
    expect(find.text('Escolha o motivo.'), findsOneWidget);
    await tester.tap(find.text('Outro'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Paralisar'));
    await tester.pump();
    expect(find.text('Escreva a observação para "Outro".'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Vazamento de gás na rua');
    await tester.tap(find.widgetWithText(FilledButton, 'Paralisar'));
    await tester.pumpAndSettle();

    final e = armazem.fila.single.evento;
    expect(
      (e.acao, e.motivoId, e.observacao, e.sequencia),
      (AcaoDeCampo.paralisar, 'm2', 'Vazamento de gás na rua', 2),
    );
    expect(find.text('Paralisada'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Retomar OS'), findsOneWidget);
  });

  testWidgets('encerrar executada: corrige o formulário, tira a foto e salva na fila', (tester) async {
    await abrirOs(tester);
    await tocar(tester, find.widgetWithText(FilledButton, 'Encerrar OS'));
    await tester.pumpAndSettle();

    // A extensão só aparece quando a ligação é viável.
    expect(find.text('Extensão do ramal *'), findsNothing);
    await tester.tap(find.text('Sim'));
    await tester.pumpAndSettle();
    expect(find.text('Extensão do ramal *'), findsOneWidget);

    final salvar = find.widgetWithText(FilledButton, 'Salvar encerramento');
    await rolarAte(tester, salvar);
    await tester.tap(salvar);
    await tester.pumpAndSettle();
    expect(find.text('Corrija "Extensão do ramal" para encerrar.'), findsOneWidget);
    expect(armazem.fila, isEmpty);

    await rolarAte(tester, find.text('Extensão do ramal *'), paraCima: true);
    await tester.enterText(find.widgetWithText(TextFormField, 'Extensão do ramal *'), '12,5');
    await tocar(tester, find.text('150 mm'));
    await rolarAte(tester, find.text('Câmera'));
    await tester.tap(find.text('Câmera'));
    await tester.pumpAndSettle();
    expect(find.text('1 de 1 a 2'), findsOneWidget);

    await rolarAte(tester, salvar);
    await tester.tap(salvar);
    await tester.pumpAndSettle();

    // De volta à lista; o encerramento e a foto estão na fila.
    expect(find.textContaining('1 ação e 1 foto pendentes'), findsOneWidget);
    final e = armazem.fila.single.evento;
    final foto = armazem.anexos.single;
    expect(e.acao, AcaoDeCampo.encerrar);
    expect(e.resultado, 'EXECUTADA');
    expect(e.quantidade, 1);
    expect(e.valores, {
      'viavel': true,
      'extensao': 12.5,
      'diametro': '150 mm',
      'fachada': [foto.id],
    });
    expect((foto.osId, foto.parametro), ('a', 'fachada'));
    expect(arquivos.arquivos.keys, [foto.caminho]);
  });

  testWidgets('encerrar não executada pede o motivo', (tester) async {
    await abrirOs(tester);
    await tocar(tester, find.widgetWithText(FilledButton, 'Encerrar OS'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Não executada'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Morador sem interesse'));
    final salvar = find.widgetWithText(FilledButton, 'Salvar encerramento');
    await rolarAte(tester, salvar);
    await tester.tap(salvar);
    await tester.pumpAndSettle();
    final e = armazem.fila.single.evento;
    expect((e.resultado, e.motivoId, e.valores), ('NAO_EXECUTADA', 'm4', null));
  });

  testWidgets('sair do encerramento sem salvar apaga as fotos tiradas', (tester) async {
    await abrirOs(tester);
    await tocar(tester, find.widgetWithText(FilledButton, 'Encerrar OS'));
    await tester.pumpAndSettle();
    await rolarAte(tester, find.text('Câmera'));
    await tester.tap(find.text('Câmera'));
    await tester.pumpAndSettle();
    expect(arquivos.arquivos, hasLength(1));
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(arquivos.arquivos, isEmpty);
    expect(armazem.fila, isEmpty);
  });

  for (final brilho in Brightness.values) {
    testWidgets('a OS e o encerramento passam nas diretrizes de acessibilidade (${brilho.name})', (tester) async {
      final semantica = tester.ensureSemantics();
      await tester.pumpWidget(app(brilho: brilho));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Ver OS'));
      await tester.pumpAndSettle();
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await tocar(tester, find.widgetWithText(FilledButton, 'Encerrar OS'));
      await tester.pumpAndSettle();
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      semantica.dispose();
    });
  }
}
