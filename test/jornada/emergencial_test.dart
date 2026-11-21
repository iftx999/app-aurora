import 'package:aurora_campo/app/dependencias.dart';
import 'package:aurora_campo/autenticacao/cofre.dart';
import 'package:aurora_campo/dados/aparelho.dart';
import 'package:aurora_campo/dados/local/arquivos_de_foto.dart';
import 'package:aurora_campo/dados/local/armazem_do_dia.dart';
import 'package:aurora_campo/jornada/controle_do_dia.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../apoio.dart';

/// ADR 0051: OS emergencial que entra durante a jornada toca o alerta e aparece em destaque.
void main() {
  late ApiFalsa api;
  late ArmazemEmMemoria armazem;
  late AparelhoFalso aparelho;
  ProviderContainer? aberto;

  ControleDoDia controle() => aberto!.read(controleDoDiaProvider.notifier);
  EstadoDoDia estado() => aberto!.read(controleDoDiaProvider);

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

  /// Diferença do pacote com a emergencial "e" programada para a equipe.
  final comEmergencial = pacoteJson(
    diferenca: true,
    versao: 101,
    ordens: [ordemJson('e', prioridade: 'EMERGENCIAL', servico: 'Desobstrução de rede', rua: 'R. Boa Morte')],
    ids: const ['a', 'b', 'c', 'e'],
  );

  setUp(() {
    api = ApiFalsa(equipes: equipesDeTeste);
    aparelho = AparelhoFalso();
    armazem = ArmazemEmMemoria()..pacote = (pacote: pacoteJson(), baixadoEm: agoraDosTestes);
    api.respostasDoPacote.add(pacoteJson(diferenca: true, ordens: const [], ids: const ['a', 'b', 'c']));
  });

  tearDown(() {
    aberto?.dispose();
    aberto = null;
  });

  test('a emergencial que já estava no começo da jornada não toca; a que entra depois toca uma vez', () async {
    criar();
    await controle().carregar();
    // "c" é emergencial desde o início.
    expect(armazem.emergenciaisAvisadas, ['c']);
    expect(aparelho.avisos, isEmpty);

    api.respostasDoPacote
      ..clear()
      ..add(comEmergencial);
    await controle().atualizar();
    expect(estado().emergenciasNovas, ['e']);
    final aviso = aparelho.avisos.single;
    expect(aviso.canal, CanalDeAviso.emergencial);
    expect(aviso.titulo, 'OS emergencial nova');
    expect(aviso.texto, startsWith('Desobstrução de rede · R. Boa Morte'));

    // De novo (sem novidade): não toca outra vez.
    await controle().atualizar();
    expect(aparelho.avisos, hasLength(1));

    controle().dispensarEmergencias();
    expect(estado().emergenciasNovas, isEmpty);
  });

  test('chega sozinha pela conferência a cada 2 min, sem o agente puxar a tela', () {
    fakeAsync((tempo) {
      criar();
      controle().carregar();
      tempo.flushMicrotasks();
      api.respostasDoPacote
        ..clear()
        ..add(comEmergencial);
      tempo.elapse(ControleDoDia.intervaloDaRota + const Duration(seconds: 1));
      expect(estado().emergenciasNovas, ['e']);
      expect(aparelho.avisos.single.canal, CanalDeAviso.emergencial);
    });
  });

  test('encerrar a jornada esquece as avisadas', () async {
    criar();
    await controle().carregar();
    await controle().encerrar();
    expect(armazem.emergenciaisAvisadas, isNull);
  });
}
