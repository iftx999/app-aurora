import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../app/dependencias.dart';
import '../autenticacao/estado_sessao.dart';
import '../dados/api/api_campo.dart';
import '../dados/api/erros.dart';
import '../dados/local/armazem_do_dia.dart';
import '../dados/localizacao.dart';
import '../dados/modelos/dia.dart';
import '../dados/modelos/evento.dart';
import '../dados/modelos/foto.dart';
import '../dados/modelos/rota.dart';
import '../sincronizacao/controle_da_fila.dart';

/// O dia no celular: equipes, pacote baixado e jornada (J8; 10.9.2).
class EstadoDoDia {
  const EstadoDoDia({
    this.carregado = false,
    this.equipes,
    this.pacote,
    this.baixadoEm,
    this.inicioPendente,
    this.ocupado = false,
    this.semSinal = false,
    this.erro,
    this.abrirAjustes = false,
    this.rota,
  });

  /// Já leu o que estava guardado no celular.
  final bool carregado;

  /// Nulo até a primeira resposta da API (sem sinal, fica nulo).
  final List<EquipeDoDia>? equipes;
  final PacoteDoDia? pacote;
  final DateTime? baixadoEm;

  /// Jornada iniciada sem sinal, ainda não enviada.
  final InicioPendente? inicioPendente;
  final bool ocupado;

  /// A última tentativa de falar com a API falhou por rede.
  final bool semSinal;
  final String? erro;

  /// O erro só se resolve nos ajustes do Android (permissão negada de vez).
  final bool abrirAjustes;

  /// Rota publicada da equipe (mapa); nula até haver uma.
  final RotaDoDia? rota;

  bool get emJornada => inicioPendente != null || (pacote?.jornada?.aberta ?? false);

  EstadoDoDia copiar({
    bool? carregado,
    List<EquipeDoDia>? equipes,
    PacoteDoDia? pacote,
    bool semPacote = false,
    DateTime? baixadoEm,
    InicioPendente? Function()? inicioPendente,
    bool? ocupado,
    bool? semSinal,
    String? Function()? erro,
    bool? abrirAjustes,
    RotaDoDia? Function()? rota,
  }) => EstadoDoDia(
    carregado: carregado ?? this.carregado,
    equipes: equipes ?? this.equipes,
    pacote: semPacote ? null : (pacote ?? this.pacote),
    baixadoEm: semPacote ? null : (baixadoEm ?? this.baixadoEm),
    inicioPendente: inicioPendente == null ? this.inicioPendente : inicioPendente(),
    ocupado: ocupado ?? this.ocupado,
    semSinal: semSinal ?? this.semSinal,
    erro: erro == null ? this.erro : erro(),
    abrirAjustes: abrirAjustes ?? this.abrirAjustes,
    rota: semPacote ? null : (rota == null ? this.rota : rota()),
  );
}

final controleDoDiaProvider = NotifierProvider<ControleDoDia, EstadoDoDia>(ControleDoDia.new);

class ControleDoDia extends Notifier<EstadoDoDia> {
  EstadoDoDia _ultimo = const EstadoDoDia();

  // Chamadas em andamento quando a sessão acaba não mexem mais no estado.
  @override
  EstadoDoDia get state => ref.mounted ? super.state : _ultimo;

  @override
  set state(EstadoDoDia novo) {
    _ultimo = novo;
    if (ref.mounted) {
      super.state = novo;
      ref.read(posicoesLiberadasProvider.notifier).definir(novo.carregado && novo.inicioPendente == null);
    }
  }

  /// O pacote como o servidor mandou; [EstadoDoDia.pacote] é ele com as ações do celular por cima.
  PacoteDoDia? _doServidor;

  ArmazemDoDia get _armazem => ref.read(armazemProvider);
  DateTime _agora() => ref.read(relogioProvider)();

  @override
  EstadoDoDia build() {
    // Saiu, trocou de empresa ou teve o celular revogado: o próximo login começa do zero.
    ref.listen(sessaoProvider, (anterior, novo) {
      final saiu = anterior is Desbloqueada || anterior is Bloqueada;
      if (saiu && (novo is SemLogin || novo is SemEmpresa || novo is Revogada)) ref.invalidateSelf();
    });
    // Cada mudança da fila (ação nova, resposta do servidor) redesenha a situação das OS.
    ref.listen(filaProvider.select((f) => f.versao), (_, _) => _mostrar());
    ref.listen(filaProvider.select((f) => f.recebimentos), (_, _) => aoReceberDaFila());
    ref.onDispose(() {
      for (final t in _consultasDaRota) {
        t.cancel();
      }
    });
    _carga = Future.microtask(_carregar);
    return const EstadoDoDia();
  }

  Future<void>? _carga;

  /// A rota da jornada é calculada no servidor depois do início (ADR 0048): o app pergunta de novo algumas vezes.
  static const consultasDaRota = [Duration(seconds: 15), Duration(seconds: 45)];
  final _consultasDaRota = <Timer>[];
  String? _etagDaRota;

  /// Lê o que está no celular e tenta atualizar pela API (uma vez por sessão; depois, [atualizar]).
  Future<void> carregar() => _carga ??= _carregar();

  Future<void> _carregar() async {
    final guardado = await _armazem.lerPacote();
    final pendente = await _armazem.lerInicioPendente();
    final rota = await _armazem.lerRota();
    _doServidor = guardado == null ? null : PacoteDoDia(guardado.pacote);
    _etagDaRota = rota?.etag;
    state = state.copiar(
      carregado: true,
      baixadoEm: guardado?.baixadoEm,
      inicioPendente: () => pendente,
      rota: () => rota == null ? null : RotaDoDia(rota.rota),
    );
    await _mostrar();
    await atualizar();
  }

  /// Envia o início pendente, busca as equipes e, em jornada, as mudanças do pacote.
  Future<void> atualizar() => _comApi(() async {
    final pendente = state.inicioPendente;
    if (pendente != null) {
      await _guardar(
        await ref
            .read(apiCampoProvider)
            .iniciarJornada(
              id: pendente.id,
              equipeId: pendente.equipeId,
              ocorridoEm: pendente.ocorridoEm,
              posicao: _posicao(pendente.posicao),
            ),
      );
      await _armazem.guardarInicioPendente(null);
      state = state.copiar(inicioPendente: () => null);
      _consultarRotaEmSeguida();
    }
    final equipes = await ref.read(apiCampoProvider).equipes();
    state = state.copiar(equipes: equipes);
    final pacote = _doServidor;
    if (pacote != null && state.emJornada) {
      final resposta = await ref
          .read(apiCampoProvider)
          .pacote(desde: _deHoje(pacote) ? pacote.versao : null, equipe: pacote.equipeId);
      await _guardar(resposta);
    }
    if (state.emJornada) await _atualizarRota();
  });

  /// Baixa a rota só quando mudou (ETag). Sem jornada no servidor (409), fica a que estava.
  Future<void> _atualizarRota() async {
    try {
      final r = await ref.read(apiCampoProvider).rota(conhecida: _etagDaRota);
      if (!r.mudou) return;
      await _armazem.guardarRota(r.json, etag: r.etag);
      _etagDaRota = r.etag;
      state = state.copiar(rota: () => r.json == null ? null : RotaDoDia(r.json!));
    } on ErroDaApi catch (e) {
      if (e.celularRevogado) rethrow;
    }
  }

  void _consultarRotaEmSeguida() {
    for (final espera in consultasDaRota) {
      _consultasDaRota.add(
        Timer(espera, () {
          if (ref.mounted && state.emJornada && state.rota?.origem != 'JORNADA') unawaited(atualizar());
        }),
      );
    }
  }

  /// J8: lê o GPS e abre a jornada. Sem sinal, segue com a programação já baixada da equipe e envia o início depois.
  Future<void> iniciar(String equipeId) async {
    if (state.ocupado) return;
    state = state.copiar(ocupado: true, erro: () => null, abrirAjustes: false);
    final Posicao posicao;
    try {
      posicao = await ref.read(localizacaoProvider).atual();
    } on GpsIndisponivel catch (e) {
      state = state.copiar(ocupado: false, erro: () => e.mensagem, abrirAjustes: e.abrirAjustes);
      return;
    }
    final inicio = InicioPendente(
      id: const Uuid().v4(),
      equipeId: equipeId,
      ocorridoEm: _agora(),
      posicao: posicao.paraJson().cast<String, dynamic>(),
    );
    state = state.copiar(ocupado: false);
    await _comApi(
      () async {
        await _guardar(
          await ref
              .read(apiCampoProvider)
              .iniciarJornada(id: inicio.id, equipeId: equipeId, ocorridoEm: inicio.ocorridoEm, posicao: posicao),
        );
        state = state.copiar(equipes: await ref.read(apiCampoProvider).equipes());
        // A do programador já aparece; a calculada da posição chega nas consultas seguintes.
        await _atualizarRota();
        _consultarRotaEmSeguida();
      },
      semSinal: () async {
        final pacote = state.pacote;
        if (pacote == null || pacote.equipeId != equipeId || !_deHoje(pacote)) {
          state = state.copiar(
            erro: () =>
                'Sem sinal e sem a programação de hoje desta equipe no celular. '
                'Procure um lugar com sinal para iniciar.',
          );
          return;
        }
        await _armazem.guardarInicioPendente(inicio);
        state = state.copiar(inicioPendente: () => inicio);
      },
    );
  }

  /// J9: registra a ação na fila **antes** de mudar a tela (10.9.3), com hora, GPS (se houver) e a sequência da OS;
  /// o envio sai em seguida, ou quando o sinal voltar.
  Future<void> registrar(
    String osId,
    AcaoDeCampo acao, {
    String? motivoId,
    String? observacao,
    String? resultado,
    num? quantidade,
    Map<String, dynamic>? valores,
    List<FotoDaOs> fotos = const [],
  }) async {
    final ordem = state.pacote?.ordens.where((o) => o.id == osId).firstOrNull;
    if (ordem == null || acao.destino(ordem.status) == null) {
      state = state.copiar(erro: () => '${acao.rotulo} não é possível nesta OS agora.');
      return;
    }
    Posicao? posicao;
    try {
      posicao = await ref.read(localizacaoProvider).atual();
    } on GpsIndisponivel {
      // RN-22: sem GPS a ação vale; o servidor marca a falta da posição.
    }
    final sequencia = [ordem.ultimaSequencia, await _armazem.ultimaSequencia(osId)].reduce((a, b) => a > b ? a : b) + 1;
    await ref
        .read(filaProvider.notifier)
        .sincronizador
        .registrar(
          EventoDeCampo(
            id: const Uuid().v4(),
            osId: osId,
            sequencia: sequencia,
            acao: acao,
            ocorridoEm: _agora(),
            motivoId: motivoId,
            observacao: observacao,
            resultado: resultado,
            quantidade: quantidade,
            valores: valores,
            posicao: posicao?.paraJson().cast<String, dynamic>(),
            versaoPacote: _doServidor?.versao,
          ),
          fotos: fotos,
        );
    await _mostrar();
  }

  /// O servidor recebeu eventos: baixa as mudanças do pacote (situação oficial das OS, removidas).
  Future<void> aoReceberDaFila() async {
    if (state.emJornada && !state.ocupado) await atualizar();
  }

  /// J8: encerra a jornada; nenhuma OS pode estar em execução e a fila precisa ter saído.
  Future<void> encerrar() async {
    final pacote = state.pacote;
    if (pacote?.emExecucao != null) {
      state = state.copiar(erro: () => 'Paralise ou encerre a OS em execução antes de encerrar a jornada.');
      return;
    }
    final fila = ref.read(filaProvider.notifier).sincronizador;
    await fila.enviar();
    if (fila.estado.pendentes > 0) {
      final n = fila.estado.pendentes;
      state = state.copiar(
        erro: () => 'Ainda ${n == 1 ? 'há 1 ação' : 'há $n ações'} na fila. Encerre a jornada quando forem enviadas.',
      );
      return;
    }
    if (state.inicioPendente != null) {
      // Ainda não chegou ao servidor: tenta enviar antes.
      await atualizar();
      if (state.inicioPendente != null) {
        state = state.copiar(erro: () => 'Sem sinal: o início da jornada ainda não foi enviado. Encerre com sinal.');
        return;
      }
    }
    await _comApi(() async {
      await ref.read(apiCampoProvider).encerrarJornada(_agora());
      // 10.9.6: o pacote antigo sai do celular ao encerrar a jornada.
      await _armazem.apagarPacote();
      await _armazem.guardarRota(null);
      _etagDaRota = null;
      _doServidor = null;
      state = state.copiar(semPacote: true);
      state = state.copiar(equipes: await ref.read(apiCampoProvider).equipes());
    }, semSinal: () async => state = state.copiar(erro: () => 'Sem sinal: encerre a jornada quando houver conexão.'));
  }

  void dispensarErro() => state = state.copiar(erro: () => null, abrirAjustes: false);

  Future<void> _guardar(Map<String, dynamic> resposta) async {
    final atual = _doServidor;
    final novo = atual == null || resposta['diferenca'] != true ? PacoteDoDia(resposta) : atual.aplicar(resposta);
    final agora = _agora();
    await _armazem.guardarPacote(novo.json, agora);
    _doServidor = novo;
    state = state.copiar(baixadoEm: agora);
    await _mostrar();
  }

  /// Pacote do servidor + as ações que ele ainda não reflete: as da fila, as que esperam o anterior e as recebidas
  /// depois do último download. Recusadas e superadas não valem.
  Future<void> _mostrar() async {
    final pacote = _doServidor;
    if (pacote == null) {
      state = state.copiar(semPacote: true, baixadoEm: state.baixadoEm);
      return;
    }
    final baixado = state.baixadoEm;
    final acoes = (await _armazem.eventos())
        .where(
          (e) =>
              e.situacao.valeNoCelular &&
              (e.situacao == SituacaoDoEnvio.pendente ||
                  e.situacao == SituacaoDoEnvio.aguardando ||
                  baixado == null ||
                  (e.respondidoEm?.isAfter(baixado) ?? true)),
        )
        .map((e) => (osId: e.evento.osId, destino: e.evento.acao.destino));
    state = state.copiar(pacote: pacote.comAcoes(acoes));
  }

  /// Roda a chamada marcando ocupado; falta de rede vira [semSinal] (ou o aviso), revogação apaga tudo.
  Future<void> _comApi(Future<void> Function() chamada, {Future<void> Function()? semSinal}) async {
    state = state.copiar(ocupado: true);
    try {
      await chamada();
      state = state.copiar(semSinal: false);
    } on SemConexao {
      state = state.copiar(semSinal: true);
      await semSinal?.call();
    } on ErroDaApi catch (e) {
      if (e.celularRevogado) {
        await ref.read(sessaoProvider.notifier).sessao.revogar();
        return;
      }
      state = state.copiar(erro: () => e.mensagem);
    } finally {
      state = state.copiar(ocupado: false);
    }
  }

  bool _deHoje(PacoteDoDia p) {
    final g = p.geradoEm.toLocal(), h = _agora();
    return g.year == h.year && g.month == h.month && g.day == h.day;
  }

  static Posicao _posicao(Map<String, dynamic> j) => Posicao(
    (j['latitude'] as num).toDouble(),
    (j['longitude'] as num).toDouble(),
    precisaoM: (j['precisaoM'] as num?)?.toDouble(),
  );
}
