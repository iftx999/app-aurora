import 'package:aurora_campo/app/dependencias.dart';
import 'package:aurora_campo/autenticacao/cofre.dart';
import 'package:aurora_campo/dados/api/erros.dart';
import 'package:aurora_campo/dados/local/arquivos_de_foto.dart';
import 'package:aurora_campo/dados/local/armazem_do_dia.dart';
import 'package:aurora_campo/jornada/controle_do_dia.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../apoio.dart';

/// J7 (ADR 0050): a nova ordem publicada no meio da jornada espera o agente confirmar.
void main() {
  late ApiFalsa api;
  late ArmazemEmMemoria armazem;
  late AparelhoFalso aparelho;
  ProviderContainer? aberto;

  ControleDoDia controle() => aberto!.read(controleDoDiaProvider.notifier);
  EstadoDoDia estado() => aberto!.read(controleDoDiaProvider);
  List<String> lista() => [for (final o in estado().pacote!.ordens) o.id];

  void criar() {
    aberto = ProviderContainer(
      overrides: [
        apiCampoProvider.overrideWithValue(api),
        armazemProvider.overrideWithValue(armazem),
        arquivosDeFotoProvider.overrideWithValue(ArquivosEmMemoria()),
        localizacaoProvider.overrideWithValue(GpsFalso()),
        fonteDePosicoesProvider.overrideWithValue(PosicoesFalsas()),
        aparelhoProvider.overrideWithValue(aparelho),
        relogioProvider.overrideWithValue(() => agoraDosTestes),
        cofreProvider.overrideWithValue(CofreEmMemoria()),
      ],
    )..listen(controleDoDiaProvider, (_, _) {});
  }

  /// Pacote do servidor já na ordem nova (a publicação reprograma a sequência): c, a, b.
  Map<String, dynamic> pacoteNaOrdemNova() =>
      pacoteJson(ordens: [ordemJson('a', sequencia: 2), ordemJson('b', sequencia: 3), ordemJson('c', sequencia: 1)]);

  setUp(() {
    api = ApiFalsa(equipes: equipesDeTeste);
    aparelho = AparelhoFalso();
    // O celular segue a rota r1 (b, a, c), já confirmada.
    armazem = ArmazemEmMemoria()
      ..pacote = (
        pacote: pacoteJson(
          ordens: [ordemJson('a', sequencia: 2), ordemJson('b', sequencia: 1), ordemJson('c', sequencia: 3)],
        ),
        baixadoEm: agoraDosTestes,
      )
      ..rota = (rota: rotaJson(origem: 'PREVIA'), etag: '"r1"');
    api.respostasDoPacote.add(pacoteNaOrdemNova());
    api.rotaPublicada = rotaJson(
      id: 'r2',
      origem: 'REOTIMIZACAO',
      ordem: const ['c', 'a', 'b'],
      exigeConfirmacao: true,
    );
  });

  tearDown(() {
    aberto?.dispose();
    aberto = null;
  });

  test('a nova ordem fica esperando: a lista segue a anterior e o Android avisa uma vez', () async {
    criar();
    await controle().carregar();
    expect(estado().rota?.id, 'r1');
    expect(estado().rotaNova?.id, 'r2');
    expect(lista(), ['b', 'a', 'c']);
    expect(estado().pacote!.ordens.first.sequencia, 1);
    expect(armazem.rotaNova?.etag, '"r2"');
    expect(aparelho.avisos.single.titulo, 'Nova ordem das OS');
    expect(api.confirmacoesDeRota, isEmpty);

    // A mesma rota de novo (304): sem outro aviso.
    await controle().atualizar();
    expect(api.pedidosDeRota.last, '"r2"');
    expect(aparelho.avisos, hasLength(1));
  });

  test('confirmar troca a lista e avisa o servidor', () async {
    criar();
    await controle().carregar();
    await controle().confirmarRotaNova();
    expect(estado().rota?.id, 'r2');
    expect(estado().rotaNova, isNull);
    expect(lista(), ['c', 'a', 'b']);
    expect(armazem.rota?.etag, '"r2"');
    expect(armazem.rotaNova, isNull);
    expect(api.confirmacoesDeRota.single.id, 'r2');
    expect(armazem.confirmacaoPendente, isNull);
  });

  test('confirmada sem sinal: vale no celular e vai quando a conexão voltar', () async {
    criar();
    await controle().carregar();
    api.semSinal = true;
    await controle().confirmarRotaNova();
    expect(lista(), ['c', 'a', 'b']);
    expect(armazem.confirmacaoPendente?.roteirizacaoId, 'r2');
    expect(api.confirmacoesDeRota, isEmpty);

    api.semSinal = false;
    await controle().atualizar();
    expect(api.confirmacoesDeRota.single.id, 'r2');
    expect(armazem.confirmacaoPendente, isNull);
  });

  test('a rota foi substituída antes de a confirmação chegar (409): a confirmação é esquecida', () async {
    criar();
    await controle().carregar();
    api.erroNaConfirmacao = const ErroDaApi(409, 'Esta rota já foi substituída por outra.');
    await controle().confirmarRotaNova();
    expect(armazem.confirmacaoPendente, isNull);
    expect(estado().erro, isNull);
  });

  test('a do início da jornada e a primeira rota do dia não pedem confirmação', () async {
    armazem.rota = null;
    criar();
    await controle().carregar();
    // Sem rota anterior não há o que comparar: vale direto e o programador fica sabendo.
    expect(estado().rota?.id, 'r2');
    expect(estado().rotaNova, isNull);
    expect(api.confirmacoesDeRota.single.id, 'r2');
    expect(aparelho.avisos, isEmpty);
  });

  test('em jornada, a rota é conferida a cada 2 min sem o agente puxar a tela', () {
    fakeAsync((tempo) {
      api.rotaPublicada = rotaJson(origem: 'PREVIA');
      criar();
      controle().carregar();
      tempo.flushMicrotasks();
      expect(estado().rotaNova, isNull);

      api.rotaPublicada = rotaJson(
        id: 'r2',
        origem: 'REOTIMIZACAO',
        ordem: const ['c', 'a', 'b'],
        exigeConfirmacao: true,
      );
      tempo.elapse(ControleDoDia.intervaloDaRota + const Duration(seconds: 1));
      expect(estado().rotaNova?.id, 'r2');
      expect(aparelho.avisos, hasLength(1));
    });
  });

  test('sem sinal na conferência periódica, segue a ordem que já tem, sem erro', () {
    fakeAsync((tempo) {
      api.rotaPublicada = rotaJson(origem: 'PREVIA');
      criar();
      controle().carregar();
      tempo.flushMicrotasks();
      api.semSinal = true;
      tempo.elapse(ControleDoDia.intervaloDaRota + const Duration(seconds: 1));
      expect(estado().rota?.id, 'r1');
      expect(estado().erro, isNull);
    });
  });

  test('ao encerrar a jornada, a nova ordem pendente sai do celular', () async {
    criar();
    await controle().carregar();
    await controle().encerrar();
    expect(armazem.rotaNova, isNull);
    expect(estado().rotaNova, isNull);
  });
}
