import 'package:aurora_campo/dados/api/erros.dart';
import 'package:aurora_campo/dados/local/armazem_do_dia.dart';
import 'package:aurora_campo/dados/modelos/evento.dart';
import 'package:aurora_campo/sincronizacao/sincronizador.dart';
import 'package:flutter_test/flutter_test.dart';

import '../apoio.dart';

void main() {
  late ApiFalsa api;
  late ArmazemEmMemoria armazem;
  late Sincronizador sinc;
  late DateTime agora;
  var revogacoes = 0;
  var recebimentos = 0;

  setUp(() {
    api = ApiFalsa();
    armazem = ArmazemEmMemoria();
    agora = agoraDosTestes;
    revogacoes = 0;
    recebimentos = 0;
    sinc = Sincronizador(armazem: armazem, api: api, agora: () => agora, tamanhoDoLote: 2)
      ..aoRevogar = (() async => revogacoes++)
      ..aoReceber = (() => recebimentos++);
    // O relógio anda depois de criar: as respostas contam como "desta abertura".
    agora = agora.add(const Duration(seconds: 1));
  });

  tearDown(() => sinc.parar());

  Future<void> naFila(int n, {String os = 'a'}) async {
    for (var i = 1; i <= n; i++) {
      await armazem.registrarEvento(eventoDeTeste('$os$i', os: os, sequencia: i));
    }
    await sinc.recontar();
  }

  test('envia em lotes, na ordem, e marca as respostas', () async {
    await naFila(5);
    expect(sinc.estado.pendentes, 5);
    await sinc.enviar();
    expect(api.lotes.map((l) => l.map((e) => e.id).toList()), [
      ['a1', 'a2'],
      ['a3', 'a4'],
      ['a5'],
    ]);
    expect(sinc.estado.pendentes, 0);
    expect(sinc.estado.ultimoEnvio, agora);
    expect(armazem.fila.every((e) => e.situacao == SituacaoDoEnvio.aplicado), isTrue);
    expect(recebimentos, 1);
  });

  test('sem sinal: a fila fica e a próxima tentativa espera cada vez mais', () async {
    await naFila(2);
    api.semSinal = true;
    await sinc.enviar();
    expect(sinc.estado.pendentes, 2);
    expect(sinc.estado.falhasSeguidas, 1);
    expect(sinc.estado.proximaTentativa, agora.add(const Duration(seconds: 5)));
    await sinc.enviar();
    expect(sinc.estado.proximaTentativa, agora.add(const Duration(seconds: 15)));
    expect(armazem.fila.first.tentativas, 2);

    api.semSinal = false;
    await sinc.enviar();
    expect(sinc.estado.pendentes, 0);
    expect(sinc.estado.falhasSeguidas, 0);
    expect(sinc.estado.proximaTentativa, isNull);
  });

  test('envios ao mesmo tempo viram um só', () async {
    await naFila(1);
    await Future.wait([sinc.enviar(), sinc.enviar(), sinc.enviar()]);
    expect(api.lotes, hasLength(1));
  });

  test('lote que o servidor não lê é reenviado um a um e só o evento com problema é recusado', () async {
    await naFila(2);
    var primeiraVez = true;
    api.responder = (e) {
      if (primeiraVez) {
        primeiraVez = false;
        throw const ErroDaApi(400, 'Lote inválido');
      }
      if (e.id == 'a2') throw const ErroDaApi(400, 'Observação longa demais.');
      return RespostaDoEvento(id: e.id, situacao: SituacaoDoEnvio.aplicado);
    };
    await sinc.enviar();
    expect(armazem.fila.map((e) => e.situacao), [SituacaoDoEnvio.aplicado, SituacaoDoEnvio.rejeitado]);
    expect(armazem.fila.last.mensagem, 'Observação longa demais.');
    expect(sinc.estado.pendentes, 0);
    expect(sinc.estado.avisos.single.evento.id, 'a2');
  });

  test('recusado, superado e conflito viram aviso uma vez; aguardando não', () async {
    await naFila(4);
    api.responder = (e) => RespostaDoEvento(
      id: e.id,
      situacao: switch (e.id) {
        'a1' => SituacaoDoEnvio.rejeitado,
        'a2' => SituacaoDoEnvio.superado,
        'a3' => SituacaoDoEnvio.conflito,
        _ => SituacaoDoEnvio.aguardando,
      },
    );
    await sinc.enviar();
    expect(sinc.estado.avisos.map((e) => e.evento.id), ['a1', 'a2', 'a3']);
    // Aguardando já está no servidor: sai da fila de envio.
    expect(sinc.estado.pendentes, 0);
    sinc.dispensarAvisos();
    await sinc.enviar();
    expect(sinc.estado.avisos, isEmpty);
  });

  test('repetido vale pela situação da primeira vez', () {
    final r = RespostaDoEvento.deJson({'id': 'x', 'situacao': 'REPETIDO', 'original': 'CONFLITO'});
    expect(r.situacao, SituacaoDoEnvio.conflito);
  });

  test('celular revogado: termina de enviar a fila e só então revoga, uma vez', () async {
    await naFila(3);
    api.revogarNoEnvio = true;
    await sinc.enviar();
    expect(api.lotes.expand((l) => l), hasLength(3));
    expect(revogacoes, 1);
    // Parado: nada mais sai.
    await armazem.registrarEvento(eventoDeTeste('b1', os: 'b'));
    await sinc.enviar();
    expect(api.lotes, hasLength(2));
  });

  test('revogado pela sessão (403): não chama a revogação de novo ao enviar antes de apagar', () async {
    await naFila(1);
    api.revogarNoEnvio = true;
    await sinc.enviarEParar();
    expect(api.lotes, hasLength(1));
    expect(revogacoes, 0);
  });

  test('respondidos há mais de 2 dias saem do celular; pendentes nunca', () async {
    await naFila(1);
    await sinc.enviar();
    await armazem.registrarEvento(eventoDeTeste('b1', os: 'b'));
    api.semSinal = true;
    agora = agora.add(const Duration(days: 3));
    await sinc.enviar();
    expect(armazem.fila.map((e) => e.evento.id), ['b1']);
  });
}
