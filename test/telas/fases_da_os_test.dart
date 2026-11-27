import 'package:aurora_campo/app/dependencias.dart';
import 'package:aurora_campo/app/tema.dart';
import 'package:aurora_campo/autenticacao/cofre.dart';
import 'package:aurora_campo/dados/local/arquivos_de_foto.dart';
import 'package:aurora_campo/dados/local/armazem_do_dia.dart';
import 'package:aurora_campo/dados/modelos/dia.dart';
import 'package:aurora_campo/dados/modelos/evento.dart';
import 'package:aurora_campo/telas/inicio/inicio_tela.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../apoio.dart';

const todas = ['INICIAR', 'PARALISAR', 'RETOMAR', 'DEVOLVER'];

/// ADR 0053: foto e observação ao iniciar, paralisar, retomar e devolver, quando o serviço exige.
void main() {
  late ApiFalsa api;
  late ArmazemEmMemoria armazem;
  late ArquivosEmMemoria arquivos;

  void montar({String status = 'PROGRAMADA', List<String>? fases = todas, List<String>? observacao = todas}) {
    api = ApiFalsa(equipes: equipesDeTeste);
    final pacote = pacoteJson(
      ordens: [
        ordemJson(
          'a',
          sequencia: 1,
          status: status,
          ultimaSequencia: status == 'PROGRAMADA' ? 0 : 1,
          fasesComFoto: fases,
          fasesComObservacao: observacao,
        ),
      ],
    );
    api.respostasDoPacote.add(pacoteJson(diferenca: true, ordens: const [], ids: const ['a']));
    armazem = ArmazemEmMemoria()..pacote = (pacote: pacote, baixadoEm: agoraDosTestes);
    arquivos = ArquivosEmMemoria();
  }

  Widget app() => ProviderScope(
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
    child: MaterialApp(theme: temaAurora(Brightness.light), home: const InicioTela()),
  );

  Future<void> abrirOs(WidgetTester tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    api.semSinal = true;
    await tester.tap(find.widgetWithText(OutlinedButton, 'Ver OS'));
    await tester.pumpAndSettle();
  }

  Future<void> tocar(WidgetTester tester, Finder alvo) async {
    await tester.ensureVisible(alvo);
    await tester.pumpAndSettle();
    await tester.tap(alvo);
    await tester.pumpAndSettle();
  }

  test('o pacote traz as fases com foto; servidor antigo não exige nenhuma', () {
    final com = OrdemDoDia.deJson(ordemJson('a', fasesComFoto: const ['INICIAR', 'DEVOLVER']));
    expect(com.exigeFoto(AcaoDeCampo.iniciar), isTrue);
    expect(com.exigeFoto(AcaoDeCampo.paralisar), isFalse);
    expect(com.comStatus(StatusOrdem.emExecucao).exigeFoto(AcaoDeCampo.devolver), isTrue);
    expect(OrdemDoDia.deJson(ordemJson('a')).fasesComFoto, isEmpty);
    final obs = OrdemDoDia.deJson(ordemJson('a', fasesComObservacao: const ['RETOMAR']));
    expect((obs.exigeObservacao(AcaoDeCampo.retomar), obs.exigeObservacao(AcaoDeCampo.iniciar)), (true, false));
    expect(OrdemDoDia.deJson(ordemJson('a')).fasesComObservacao, isEmpty);
  });

  test('o evento leva os ids das fotos e volta igual da fila', () {
    final e = EventoDeCampo(
      id: 'e1',
      osId: 'a',
      sequencia: 1,
      acao: AcaoDeCampo.iniciar,
      ocorridoEm: agoraDosTestes,
      fotos: const ['f1', 'f2'],
    );
    expect(e.paraJson()['fotos'], ['f1', 'f2']);
    expect(EventoDeCampo.deJson(e.paraJson().cast<String, dynamic>()).fotos, ['f1', 'f2']);
    expect(eventoDeTeste('e2').paraJson().containsKey('fotos'), isFalse);
  });

  testWidgets('iniciar com foto e observação exigidas: pede as duas antes e manda junto', (tester) async {
    montar();
    await abrirOs(tester);
    await tocar(tester, find.widgetWithText(FilledButton, 'Iniciar OS'));
    expect(find.text('Foto do local antes de começar *'), findsOneWidget);

    await tocar(tester, find.widgetWithText(FilledButton, 'Iniciar OS'));
    expect(find.text('Tire pelo menos uma foto para iniciar a OS.'), findsOneWidget);
    expect(armazem.fila, isEmpty);

    await tocar(tester, find.text('Câmera'));
    expect(find.text('1 de até 10'), findsOneWidget);
    expect(find.text('Tire pelo menos uma foto para iniciar a OS.'), findsNothing);
    await tocar(tester, find.widgetWithText(FilledButton, 'Iniciar OS'));
    expect(find.text('Escreva a observação para iniciar a OS.'), findsOneWidget);
    expect(armazem.fila, isEmpty);
    await tester.enterText(find.byType(TextField), '  Calçada quebrada na frente  ');
    await tester.pump();
    expect(find.text('Escreva a observação para iniciar a OS.'), findsNothing);
    await tocar(tester, find.widgetWithText(FilledButton, 'Iniciar OS'));

    final e = armazem.fila.single.evento;
    final foto = armazem.anexos.single;
    expect(e.acao, AcaoDeCampo.iniciar);
    expect(e.observacao, 'Calçada quebrada na frente');
    expect(e.fotos, [foto.id]);
    expect((foto.osId, foto.parametro), ('a', null));
    expect(arquivos.arquivos.keys, [foto.caminho]);
    // De volta à OS, agora em execução, com a foto no registro.
    expect(find.text('Em execução'), findsOneWidget);
    expect(find.textContaining('Início 09:00 · 1 foto · na fila'), findsOneWidget);
  });

  testWidgets('desistir na tela da foto apaga a foto e não registra nada', (tester) async {
    montar();
    await abrirOs(tester);
    await tocar(tester, find.widgetWithText(FilledButton, 'Iniciar OS'));
    await tocar(tester, find.text('Câmera'));
    expect(arquivos.arquivos, hasLength(1));
    await tocar(tester, find.widgetWithText(OutlinedButton, 'Cancelar'));
    expect(arquivos.arquivos, isEmpty);
    expect(armazem.fila, isEmpty);
    expect(find.text('Programada'), findsOneWidget);
  });

  testWidgets('paralisar com foto e observação exigidas: o motivo sozinho não basta', (tester) async {
    montar(status: 'EM_EXECUCAO');
    await abrirOs(tester);
    await tocar(tester, find.widgetWithText(OutlinedButton, 'Paralisar'));
    expect(find.text('Observação (obrigatória)'), findsOneWidget);
    await tester.tap(find.text('Chuva forte'));
    await tester.pump();
    await tocar(tester, find.widgetWithText(FilledButton, 'Paralisar'));
    expect(find.text('Escreva a observação para paralisar a OS.'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Vala alagada');
    await tocar(tester, find.widgetWithText(FilledButton, 'Paralisar'));
    expect(find.text('Tire pelo menos uma foto para paralisar a OS.'), findsOneWidget);

    await tocar(tester, find.text('Câmera'));
    await tocar(tester, find.text('Câmera'));
    expect(find.text('2 de até 10'), findsOneWidget);
    await tocar(tester, find.widgetWithText(FilledButton, 'Paralisar'));

    final e = armazem.fila.single.evento;
    expect((e.acao, e.motivoId, e.observacao), (AcaoDeCampo.paralisar, 'm1', 'Vala alagada'));
    expect(e.fotos, hasLength(2));
    expect(armazem.anexos.map((f) => f.id), e.fotos);
    expect(find.text('Paralisada'), findsOneWidget);
  });

  testWidgets('devolver com foto exigida', (tester) async {
    montar(status: 'EM_EXECUCAO');
    await abrirOs(tester);
    await tocar(tester, find.widgetWithText(OutlinedButton, 'Devolver'));
    expect(find.text('Foto que comprova a devolução *'), findsOneWidget);
    await tester.tap(find.byType(RadioListTile<String>).first);
    await tester.pump();
    await tocar(tester, find.text('Câmera'));
    await tester.enterText(find.byType(TextField), 'Portão trancado, ninguém atendeu');
    await tocar(tester, find.widgetWithText(FilledButton, 'Devolver'));
    final e = armazem.fila.single.evento;
    expect((e.acao, e.fotos.length, e.observacao), (AcaoDeCampo.devolver, 1, 'Portão trancado, ninguém atendeu'));
  });

  testWidgets('só a observação exigida: a tela da fase não abre a câmera', (tester) async {
    montar(fases: const []);
    await abrirOs(tester);
    await tocar(tester, find.widgetWithText(FilledButton, 'Iniciar OS'));
    expect(find.text('Câmera'), findsNothing);
    await tocar(tester, find.widgetWithText(FilledButton, 'Iniciar OS'));
    expect(find.text('Escreva a observação para iniciar a OS.'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Tudo em ordem');
    await tocar(tester, find.widgetWithText(FilledButton, 'Iniciar OS'));
    final e = armazem.fila.single.evento;
    expect(e.observacao, 'Tudo em ordem');
    expect(e.fotos, isEmpty);
  });

  testWidgets('serviço sem exigência nas fases: iniciar e paralisar como antes', (tester) async {
    montar(fases: const [], observacao: const []);
    await abrirOs(tester);
    await tocar(tester, find.widgetWithText(FilledButton, 'Iniciar OS'));
    expect(armazem.fila.single.evento.acao, AcaoDeCampo.iniciar);
    expect(armazem.fila.single.evento.fotos, isEmpty);
    await tocar(tester, find.widgetWithText(OutlinedButton, 'Paralisar'));
    expect(find.text('Câmera'), findsNothing);
    expect(find.text('Observação (opcional)'), findsOneWidget);
  });

  testWidgets('a tela da fase passa nas diretrizes de acessibilidade', (tester) async {
    final semantica = tester.ensureSemantics();
    montar();
    await abrirOs(tester);
    await tocar(tester, find.widgetWithText(FilledButton, 'Iniciar OS'));
    await tocar(tester, find.text('Câmera'));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    semantica.dispose();
  });
}
