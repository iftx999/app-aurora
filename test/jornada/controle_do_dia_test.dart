import 'package:aurora_campo/app/dependencias.dart';
import 'package:aurora_campo/autenticacao/cofre.dart';
import 'package:aurora_campo/dados/local/arquivos_de_foto.dart';
import 'package:aurora_campo/dados/local/armazem_do_dia.dart';
import 'package:aurora_campo/dados/localizacao.dart';
import 'package:aurora_campo/dados/modelos/dia.dart';
import 'package:aurora_campo/dados/modelos/evento.dart';
import 'package:aurora_campo/sincronizacao/controle_da_fila.dart';
import 'package:aurora_campo/jornada/controle_do_dia.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../apoio.dart';

void main() {
  late ApiFalsa api;
  late ArmazemEmMemoria armazem;
  late GpsFalso gps;
  ProviderContainer? aberto;
  ProviderContainer container() => aberto!;

  ControleDoDia controle() => container().read(controleDoDiaProvider.notifier);
  EstadoDoDia estado() => container().read(controleDoDiaProvider);

  Future<void> abrir() async {
    aberto = ProviderContainer(
      overrides: [
        apiCampoProvider.overrideWithValue(api),
        armazemProvider.overrideWithValue(armazem),
        arquivosDeFotoProvider.overrideWithValue(ArquivosEmMemoria()),
        localizacaoProvider.overrideWithValue(gps),
        fonteDePosicoesProvider.overrideWithValue(PosicoesFalsas()),
        aparelhoProvider.overrideWithValue(AparelhoFalso()),
        relogioProvider.overrideWithValue(() => agoraDosTestes),
        cofreProvider.overrideWithValue(CofreEmMemoria()),
      ],
    );
    container().listen(controleDoDiaProvider, (_, _) {});
    await controle().carregar();
  }

  setUp(() {
    api = ApiFalsa(equipes: equipesDeTeste);
    armazem = ArmazemEmMemoria();
    gps = GpsFalso();
  });

  tearDown(() {
    aberto?.dispose();
    aberto = null;
  });

  group('pacote do dia', () {
    test('ordena pela rota e aponta a próxima aberta', () {
      final p = PacoteDoDia(pacoteJson());
      expect(p.ordens.map((o) => o.id), ['b', 'a', 'c']);
      expect(p.atual?.id, 'a');
      expect(p.abertas, 2);
      expect(p.ordens.first.endereco, 'R. XV de Novembro, 410');
    });

    test('aplica a diferença: troca as alteradas e tira as que saíram', () {
      final p = PacoteDoDia(pacoteJson());
      final novo = p.aplicar(
        pacoteJson(
          versao: 200,
          diferenca: true,
          ordens: [
            ordemJson('a', sequencia: 2, status: 'EM_EXECUCAO'),
            ordemJson('d', sequencia: 4),
          ],
          ids: ['a', 'b', 'd'],
        ),
      );
      expect(novo.versao, 200);
      expect(novo.ordens.map((o) => o.id), ['b', 'a', 'd']);
      expect(novo.emExecucao?.id, 'a');
      expect(novo.json['diferenca'], isFalse);
    });
  });

  test('sem jornada: busca as equipes e não baixa pacote', () async {
    await abrir();
    expect(estado().equipes, hasLength(2));
    expect(estado().emJornada, isFalse);
    expect(api.pedidosDePacote, isEmpty);
  });

  test('iniciar com sinal envia a posição e guarda o pacote no celular', () async {
    await abrir();
    await controle().iniciar(equipeRede);
    expect(api.inicios.single['equipeId'], equipeRede);
    expect(api.inicios.single['latitude'], -22.5645);
    expect(estado().emJornada, isTrue);
    expect(estado().pacote?.ordens, hasLength(3));
    expect(armazem.pacote?.pacote['equipeId'], equipeRede);
    expect(armazem.inicio, isNull);
  });

  test('GPS indisponível não inicia', () async {
    gps.falha = const GpsIndisponivel('Ligue a localização do celular para iniciar a jornada.');
    await abrir();
    await controle().iniciar(equipeRede);
    expect(api.inicios, isEmpty);
    expect(estado().erro, contains('Ligue a localização'));
    expect(estado().emJornada, isFalse);
  });

  test('sem sinal, com a programação de hoje guardada: inicia e envia o início depois', () async {
    armazem.pacote = (pacote: pacoteJson(jornadaAberta: false), baixadoEm: agoraDosTestes);
    api.semSinal = true;
    await abrir();
    await controle().iniciar(equipeRede);
    expect(estado().emJornada, isTrue);
    expect(armazem.inicio?.equipeId, equipeRede);

    api
      ..semSinal = false
      ..respostasDoPacote.add(pacoteJson(diferenca: true, ordens: const [], ids: const ['a', 'b', 'c']));
    await controle().atualizar();
    expect(api.inicios.single['id'], isNotNull);
    expect(armazem.inicio, isNull);
    expect(estado().inicioPendente, isNull);
    expect(estado().pacote?.jornada?.aberta, isTrue);
  });

  test('sem sinal e sem programação da equipe: não inicia', () async {
    api.semSinal = true;
    await abrir();
    await controle().iniciar(equipeRede);
    expect(estado().emJornada, isFalse);
    expect(estado().erro, contains('Sem sinal'));
    expect(armazem.inicio, isNull);
  });

  test('em jornada, atualiza só a diferença desde a versão guardada', () async {
    armazem.pacote = (pacote: pacoteJson(versao: 100), baixadoEm: agoraDosTestes);
    api.respostasDoPacote.add(
      pacoteJson(
        versao: 150,
        diferenca: true,
        ordens: [ordemJson('c', sequencia: 3, status: 'PARALISADA')],
        ids: ['a', 'b', 'c'],
      ),
    );
    await abrir();
    expect(api.pedidosDePacote.single, (desde: 100, equipe: equipeRede));
    expect(estado().pacote?.versao, 150);
    expect(estado().pacote?.ordens.firstWhere((o) => o.id == 'c').status, StatusOrdem.paralisada);
  });

  test('pacote de outro dia é baixado inteiro', () async {
    armazem.pacote = (
      pacote: pacoteJson(versao: 100, gerado: DateTime(2026, 11, 17, 8)),
      baixadoEm: DateTime(2026, 11, 17, 8),
    );
    api.respostasDoPacote.add(pacoteJson(versao: 300));
    await abrir();
    expect(api.pedidosDePacote.single.desde, isNull);
  });

  test('encerrar com OS em execução é recusado no celular', () async {
    armazem.pacote = (
      pacote: pacoteJson(ordens: [ordemJson('a', sequencia: 1, status: 'EM_EXECUCAO')]),
      baixadoEm: agoraDosTestes,
    );
    api.respostasDoPacote.add(pacoteJson(diferenca: true, ordens: const [], ids: const ['a']));
    await abrir();
    await controle().encerrar();
    expect(api.encerramentos, 0);
    expect(estado().erro, contains('Paralise ou encerre'));
  });

  test('encerrar fecha a jornada e volta para o início', () async {
    armazem.pacote = (pacote: pacoteJson(), baixadoEm: agoraDosTestes);
    api.respostasDoPacote.add(pacoteJson(diferenca: true, ordens: const [], ids: const ['a', 'b', 'c']));
    await abrir();
    await controle().encerrar();
    expect(api.encerramentos, 1);
    expect(estado().emJornada, isFalse);
    // 10.9.6: o pacote sai do celular ao encerrar.
    expect(armazem.pacote, isNull);
  });

  group('ações na fila (J9, J10)', () {
    Future<void> emJornada({int ultimaSequencia = 0}) async {
      armazem.pacote = (
        pacote: pacoteJson(
          ordens: [
            ordemJson('a', sequencia: 1, ultimaSequencia: ultimaSequencia),
            ordemJson('b', sequencia: 2),
          ],
        ),
        baixadoEm: agoraDosTestes,
      );
      api.respostasDoPacote.add(pacoteJson(diferenca: true, ordens: const [], ids: const ['a', 'b']));
      await abrir();
      container().listen(filaProvider, (_, _) {});
    }

    StatusOrdem status(String id) => estado().pacote!.ordens.firstWhere((o) => o.id == id).status;

    test('sem sinal: a ação vale na tela, fica na fila e continua a sequência do servidor', () async {
      await emJornada(ultimaSequencia: 4);
      api.semSinal = true;
      await controle().registrar('a', AcaoDeCampo.iniciar);
      expect(status('a'), StatusOrdem.emExecucao);
      expect(estado().pacote!.atual?.id, 'a');
      final e = armazem.fila.single;
      expect(e.situacao, SituacaoDoEnvio.pendente);
      expect(e.evento.sequencia, 5);
      expect(e.evento.posicao?['latitude'], -22.5645);
      expect(e.evento.versaoPacote, 100);
      expect(container().read(filaProvider).pendentes, 1);

      // A próxima ação da mesma OS segue a numeração do celular.
      await controle().registrar('a', AcaoDeCampo.iniciar);
      expect(estado().erro, contains('não é possível'));
      expect(armazem.fila, hasLength(1));
    });

    test('com sinal: enviada na hora; recusada volta a OS para a situação do servidor', () async {
      await emJornada();
      api.responder = (e) =>
          RespostaDoEvento(id: e.id, situacao: SituacaoDoEnvio.rejeitado, mensagem: 'Fora do prazo.');
      await controle().registrar('a', AcaoDeCampo.iniciar);
      await container().read(filaProvider.notifier).sincronizador.enviar();
      await pumpEventQueue();
      expect(api.lotes.single.single.osId, 'a');
      expect(armazem.fila.single.situacao, SituacaoDoEnvio.rejeitado);
      expect(status('a'), StatusOrdem.programada);
      expect(container().read(filaProvider).avisos.single.mensagem, 'Fora do prazo.');
    });

    test('aplicada: continua valendo até o pacote novo mostrar a situação do servidor', () async {
      await emJornada();
      api.respostasDoPacote
        ..clear()
        ..add(
          pacoteJson(
            diferenca: true,
            versao: 200,
            ordens: [ordemJson('a', sequencia: 1, status: 'EM_EXECUCAO', ultimaSequencia: 1)],
            ids: const ['a', 'b'],
          ),
        );
      await controle().registrar('a', AcaoDeCampo.iniciar);
      await container().read(filaProvider.notifier).sincronizador.enviar();
      await pumpEventQueue();
      expect(estado().pacote!.versao, 200);
      expect(status('a'), StatusOrdem.emExecucao);
      expect(estado().pacote!.ordens.firstWhere((o) => o.id == 'a').ultimaSequencia, 1);
    });

    test('encerrar a jornada com a fila sem sair é recusado', () async {
      await emJornada();
      api.semSinal = true;
      await controle().registrar('b', AcaoDeCampo.devolver);
      await controle().encerrar();
      expect(estado().erro, contains('há 1 ação na fila'));
      expect(api.encerramentos, 0);
      expect(estado().emJornada, isTrue);
    });
  });
}
