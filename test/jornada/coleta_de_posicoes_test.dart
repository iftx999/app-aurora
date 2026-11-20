import 'package:aurora_campo/app/dependencias.dart';
import 'package:aurora_campo/autenticacao/cofre.dart';
import 'package:aurora_campo/dados/api/api_campo.dart';
import 'package:aurora_campo/dados/api/erros.dart';
import 'package:aurora_campo/dados/local/arquivos_de_foto.dart';
import 'package:aurora_campo/dados/local/armazem_do_dia.dart';
import 'package:aurora_campo/dados/localizacao.dart';
import 'package:aurora_campo/jornada/coleta_de_posicoes.dart';
import 'package:aurora_campo/jornada/controle_do_dia.dart';
import 'package:aurora_campo/sincronizacao/controle_da_fila.dart';
import 'package:aurora_campo/sincronizacao/sincronizador.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../apoio.dart';

/// ~0,0009° de latitude ≈ 100 m.
const _lat = -22.5645, _lon = -47.4017;

AmostraDePosicao _em(int segundos, {double norte = 0, double? precisao = 8}) => AmostraDePosicao(
  agoraDosTestes.add(Duration(seconds: segundos)),
  Posicao(_lat + norte / 111195, _lon, precisaoM: precisao),
);

void main() {
  group('amostrador (2 min ou 100 m)', () {
    test('a primeira entra; depois só com 2 min ou 100 m andados', () {
      final a = Amostrador();
      expect(a.aceita(_em(0)), isTrue);
      expect(a.aceita(_em(30, norte: 40)), isFalse, reason: '30 s e 40 m');
      expect(a.aceita(_em(60, norte: 105)), isTrue, reason: '105 m da última aceita');
      expect(a.aceita(_em(120, norte: 110)), isFalse, reason: '1 min e 5 m');
      expect(a.aceita(_em(180, norte: 110)), isTrue, reason: '2 min parado');
    });

    test('leitura imprecisa ou fora de ordem não entra', () {
      final a = Amostrador();
      expect(a.aceita(_em(0, precisao: 400)), isFalse);
      expect(a.aceita(_em(10)), isTrue);
      expect(a.aceita(_em(-300, norte: 500)), isFalse);
    });

    test('em economia: 5 min ou 250 m', () {
      final a = Amostrador()..aceita(_em(0));
      expect(a.aceita(_em(150, norte: 200), economia: true), isFalse);
      expect(a.aceita(_em(160, norte: 260), economia: true), isTrue);
      expect(a.aceita(_em(460, norte: 260), economia: true), isTrue);
    });

    test('distância pelo haversine', () {
      expect(distanciaEmMetros(const Posicao(_lat, _lon), const Posicao(_lat + 0.001, _lon)), closeTo(111.2, 0.5));
    });
  });

  group('posições na fila', () {
    late ApiFalsa api;
    late ArmazemEmMemoria armazem;
    late Sincronizador sinc;
    late DateTime agora;

    setUp(() {
      api = ApiFalsa();
      armazem = ArmazemEmMemoria();
      agora = agoraDosTestes.add(const Duration(hours: 1));
      sinc = Sincronizador(
        armazem: armazem,
        api: api,
        arquivos: ArquivosEmMemoria(),
        agora: () => agora,
        loteDePosicoes: 2,
        posicoesParaEnviar: 3,
      );
    });

    tearDown(() => sinc.parar());

    test('saem depois dos eventos, em lotes, e deixam o celular', () async {
      await armazem.registrarEvento(eventoDeTeste('a1'));
      for (var i = 0; i < 3; i++) {
        await armazem.guardarPosicao(_em(i * 120));
      }
      await sinc.recontar();
      expect(sinc.estado.posicoesPendentes, 3);
      expect(sinc.estado.vazia, isFalse);

      await sinc.enviar();
      expect(api.lotes, hasLength(1));
      expect(api.lotesDePosicoes.map((l) => l.length), [2, 1]);
      expect(armazem.filaDePosicoes, isEmpty);
      expect(sinc.estado.posicoesPendentes, 0);
      expect(sinc.estado.ultimoEnvioDePosicoes, agora);
    });

    test('só posições pendentes não prendem o fim da jornada', () async {
      await armazem.guardarPosicao(_em(0));
      await sinc.recontar();
      expect(sinc.estado.vazia, isTrue);
    });

    test('sem sinal, ficam; a leitura nova não dispara envio enquanto espera o sinal', () async {
      api.semSinal = true;
      await armazem.guardarPosicao(_em(0));
      await sinc.enviar();
      expect(sinc.estado.proximaTentativa, isNotNull);
      await sinc.registrarPosicao(_em(120));
      await sinc.registrarPosicao(_em(240));
      await Future<void>.delayed(Duration.zero);
      expect(armazem.filaDePosicoes, hasLength(3));
      expect(sinc.estado.falhasSeguidas, 1, reason: 'não tentou de novo antes da espera');
    });

    test('com algumas acumuladas, a leitura nova envia', () async {
      await sinc.registrarPosicao(_em(0));
      await sinc.registrarPosicao(_em(120));
      expect(api.lotesDePosicoes, isEmpty);
      await sinc.registrarPosicao(_em(240));
      await Future<void>.delayed(Duration.zero);
      await sinc.enviar();
      expect(api.lotesDePosicoes.expand((l) => l), hasLength(3));
    });

    test('esperam enquanto o início da jornada não chegou ao servidor', () async {
      var liberadas = false;
      sinc.podeEnviarPosicoes = () => liberadas;
      await armazem.guardarPosicao(_em(0));
      await sinc.enviar();
      expect(api.lotesDePosicoes, isEmpty);
      liberadas = true;
      await sinc.enviar();
      expect(api.lotesDePosicoes, hasLength(1));
    });

    test('sem jornada no servidor (409), o lote é descartado; servidor fora, fica', () async {
      await armazem.guardarPosicao(_em(0));
      api.erroNasPosicoes = const ErroDaApi(503, 'Fora do ar.');
      await sinc.enviar();
      expect(armazem.filaDePosicoes, hasLength(1));
      expect(sinc.estado.problema, 'Fora do ar.');

      api.erroNasPosicoes = const ErroDaApi(409, 'Posições só são registradas com a jornada aberta.');
      await sinc.enviar();
      expect(armazem.filaDePosicoes, isEmpty);
      expect(sinc.estado.problema, isNull);
    });

    test('mais velhas que 7 dias saem do celular sem envio', () async {
      api.semSinal = true;
      await armazem.guardarPosicao(
        AmostraDePosicao(agora.subtract(const Duration(days: 8)), const Posicao(_lat, _lon)),
      );
      await armazem.guardarPosicao(_em(0));
      await sinc.enviar();
      expect(armazem.filaDePosicoes.map((p) => p.amostra.momento), [agoraDosTestes]);
    });
  });

  group('coleta durante a jornada (RN-27)', () {
    late ApiFalsa api;
    late ArmazemEmMemoria armazem;
    late PosicoesFalsas fonte;
    late AparelhoFalso aparelho;
    late ProviderContainer c;

    Future<void> abrir() async {
      c = ProviderContainer(
        overrides: [
          apiCampoProvider.overrideWithValue(api),
          armazemProvider.overrideWithValue(armazem),
          arquivosDeFotoProvider.overrideWithValue(ArquivosEmMemoria()),
          localizacaoProvider.overrideWithValue(GpsFalso()),
          fonteDePosicoesProvider.overrideWithValue(fonte),
          aparelhoProvider.overrideWithValue(aparelho),
          relogioProvider.overrideWithValue(() => agoraDosTestes),
          cofreProvider.overrideWithValue(CofreEmMemoria()),
        ],
      );
      c.listen(coletaProvider, (_, _) {});
      await c.read(controleDoDiaProvider.notifier).carregar();
      await pumpEventQueue();
    }

    setUp(() {
      api = ApiFalsa(equipes: equipesDeTeste);
      armazem = ArmazemEmMemoria();
      fonte = PosicoesFalsas();
      aparelho = AparelhoFalso();
    });

    tearDown(() => c.dispose());

    test('liga ao iniciar a jornada, guarda as amostras e desliga ao encerrar', () async {
      await abrir();
      expect(fonte.assinaturas, isEmpty, reason: 'sem jornada não coleta');

      await c.read(controleDoDiaProvider.notifier).iniciar(equipeRede);
      await pumpEventQueue();
      expect(fonte.ativa, isTrue);
      expect(aparelho.pedidosDeNotificacao, 1);
      expect(c.read(coletaProvider).ativa, isTrue);

      fonte
        ..ler(agoraDosTestes, _lat, _lon)
        ..ler(agoraDosTestes.add(const Duration(seconds: 30)), _lat, _lon);
      await pumpEventQueue();
      expect(c.read(filaProvider).posicoesPendentes + api.lotesDePosicoes.expand((l) => l).length, 1);
      expect(c.read(coletaProvider).ultima, agoraDosTestes);

      api.respostasDoPacote.add(pacoteJson(diferenca: true, ordens: const [], ids: const ['a', 'b', 'c']));
      await c.read(controleDoDiaProvider.notifier).encerrar();
      await pumpEventQueue();
      expect(fonte.ativa, isFalse);
      expect(c.read(coletaProvider).ativa, isFalse);
    });

    test(
      'jornada aberta guardada no celular volta a coletar ao abrir o app; bateria baixa entra em economia',
      () async {
        aparelho.carga = (nivel: 15, carregando: false);
        armazem.pacote = (pacote: pacoteJson(), baixadoEm: agoraDosTestes);
        api.respostasDoPacote.add(pacoteJson(diferenca: true, ordens: const [], ids: const ['a', 'b', 'c']));
        await abrir();
        expect(fonte.assinaturas, [true]);
        expect(c.read(coletaProvider).economia, isTrue);
      },
    );

    test('GPS desligado no meio da jornada: avisa e tenta de novo ao voltar para o app', () async {
      armazem.pacote = (pacote: pacoteJson(), baixadoEm: agoraDosTestes);
      api.respostasDoPacote.add(pacoteJson(diferenca: true, ordens: const [], ids: const ['a', 'b', 'c']));
      await abrir();
      fonte.falhar(const GpsIndisponivel('A localização do celular foi desligada.'));
      await pumpEventQueue();
      expect(c.read(coletaProvider).problema, 'A localização do celular foi desligada.');
      expect(c.read(coletaProvider).ativa, isFalse);

      await c.read(coletaProvider.notifier).retomar();
      await pumpEventQueue();
      expect(fonte.assinaturas, hasLength(2));
      expect(c.read(coletaProvider).ativa, isTrue);
      expect(c.read(coletaProvider).problema, isNull);
    });

    test('jornada iniciada sem sinal: posições ficam até o início chegar ao servidor', () async {
      armazem.pacote = (pacote: pacoteJson(jornadaAberta: false), baixadoEm: agoraDosTestes);
      api
        ..semSinal = true
        ..respostasDoPacote.add(pacoteJson(diferenca: true, ordens: const [], ids: const ['a', 'b', 'c']));
      await abrir();
      await c.read(controleDoDiaProvider.notifier).iniciar(equipeRede);
      await pumpEventQueue();
      expect(c.read(controleDoDiaProvider).inicioPendente, isNotNull);
      expect(fonte.ativa, isTrue);

      fonte.ler(agoraDosTestes, _lat, _lon);
      await pumpEventQueue();
      api.semSinal = false;
      await c.read(filaProvider.notifier).sincronizador.enviar();
      expect(api.lotesDePosicoes, isEmpty, reason: 'o início ainda está no celular');

      await c.read(controleDoDiaProvider.notifier).atualizar();
      await c.read(filaProvider.notifier).sincronizador.enviar();
      expect(api.inicios, hasLength(1));
      expect(api.lotesDePosicoes.expand((l) => l), hasLength(1));
    });
  });
}
