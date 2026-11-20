import 'package:aurora_campo/app/dependencias.dart';
import 'package:aurora_campo/autenticacao/cofre.dart';
import 'package:aurora_campo/dados/api/erros.dart';
import 'package:aurora_campo/dados/local/arquivos_de_foto.dart';
import 'package:aurora_campo/dados/local/armazem_do_dia.dart';
import 'package:aurora_campo/dados/modelos/rota.dart';
import 'package:aurora_campo/jornada/controle_do_dia.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../apoio.dart';

void main() {
  late ApiFalsa api;
  late ArmazemEmMemoria armazem;
  ProviderContainer? aberto;
  ProviderContainer container() => aberto!;

  ControleDoDia controle() => container().read(controleDoDiaProvider.notifier);
  EstadoDoDia estado() => container().read(controleDoDiaProvider);

  void criar() {
    aberto = ProviderContainer(
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
    )..listen(controleDoDiaProvider, (_, _) {});
  }

  setUp(() {
    api = ApiFalsa(equipes: equipesDeTeste);
    armazem = ArmazemEmMemoria()..pacote = (pacote: pacoteJson(), baixadoEm: agoraDosTestes);
    api.respostasDoPacote.add(pacoteJson(diferenca: true, ordens: const [], ids: const ['a', 'b', 'c']));
  });

  tearDown(() {
    aberto?.dispose();
    aberto = null;
  });

  test('modelo: traçado em [longitude, latitude], paradas e partida', () {
    final r = RotaDoDia(rotaJson());
    expect(r.tracado.single.first.latitude, -22.5645);
    expect(r.tracado.single.first.longitude, -47.4017);
    expect(r.paradas.map((p) => p.osId), ['b', 'a', 'c']);
    expect(r.pelaMalha, isTrue);
    expect(r.km, 12.4);
    expect(r.partida?.longitude, -47.4017);
    expect(RotaDoDia(rotaJson(pelaMalha: false)).tracado, isEmpty);
  });

  test('em jornada, baixa a rota uma vez e depois só confere pelo ETag', () async {
    api.rotaPublicada = rotaJson();
    criar();
    await controle().carregar();
    expect(estado().rota?.id, 'r1');
    expect(armazem.rota?.etag, '"r1"');

    await controle().atualizar();
    expect(api.pedidosDeRota, [null, '"r1"']);
    expect(estado().rota?.id, 'r1');

    // Rota nova publicada pelo programador.
    api.rotaPublicada = rotaJson(id: 'r2', origem: 'REOTIMIZACAO');
    await controle().atualizar();
    expect(estado().rota?.origem, 'REOTIMIZACAO');
  });

  test('sem sinal, o mapa usa a rota guardada; ao encerrar, ela sai do celular', () async {
    armazem.rota = (rota: rotaJson(), etag: '"r1"');
    api.semSinal = true;
    criar();
    await controle().carregar();
    expect(estado().rota?.id, 'r1');

    api.semSinal = false;
    await controle().encerrar();
    expect(armazem.rota, isNull);
    expect(estado().rota, isNull);
  });

  test('sem jornada no servidor (409), fica a rota que estava, sem erro na tela', () async {
    armazem.rota = (rota: rotaJson(), etag: '"r1"');
    api.erroNaRota = const ErroDaApi(409, 'Não há jornada aberta.');
    criar();
    await controle().carregar();
    expect(estado().rota?.id, 'r1');
    expect(estado().erro, isNull);
  });

  test('depois de iniciar, pergunta de novo até a rota da jornada chegar', () {
    fakeAsync((tempo) {
      armazem.pacote = (pacote: pacoteJson(jornadaAberta: false), baixadoEm: agoraDosTestes);
      api.rotaPublicada = rotaJson(origem: 'PREVIA');
      criar();
      controle().carregar();
      tempo.flushMicrotasks();
      controle().iniciar(equipeRede);
      tempo.flushMicrotasks();
      expect(estado().rota?.origem, 'PREVIA');
      final pedidos = api.pedidosDeRota.length;

      api.rotaPublicada = rotaJson(id: 'r2');
      tempo.elapse(const Duration(seconds: 16));
      expect(estado().rota?.origem, 'JORNADA');
      expect(api.pedidosDeRota.length, pedidos + 1);
      // Com a rota da jornada, a segunda consulta não acontece.
      tempo.elapse(const Duration(seconds: 40));
      expect(api.pedidosDeRota.length, pedidos + 1);
    });
  });

  test('celular revogado ao pedir a rota: a sessão revoga (apaga os dados)', () async {
    api.erroNaRota = const ErroDaApi(403, 'Bloqueado', codigo: 'DISPOSITIVO_REVOGADO');
    criar();
    await controle().carregar();
    expect(estado().semSinal, isFalse);
    expect(api.pedidosDeRota, hasLength(1));
  });
}
