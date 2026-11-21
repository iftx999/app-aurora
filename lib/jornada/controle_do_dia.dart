import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../app/dependencias.dart';
import '../app/tema_do_dia.dart';
import '../autenticacao/estado_sessao.dart';
import '../dados/aparelho.dart';
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
    this.rotaNova,
    this.emergenciasNovas = const [],
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

  /// Rota publicada da equipe que vale no celular (mapa e ordem da lista); nula até haver uma.
  final RotaDoDia? rota;

  /// Nova ordem publicada no meio da jornada, esperando o agente conferir e confirmar (J7, ADR 0050). Enquanto
  /// isso, a lista segue a [rota]; sem sinal, o agente continua na ordem que já tem.
  final RotaDoDia? rotaNova;

  /// OS emergenciais que chegaram durante a jornada e o agente ainda não viu na tela (ADR 0051).
  final List<String> emergenciasNovas;

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
    RotaDoDia? Function()? rotaNova,
    List<String>? emergenciasNovas,
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
    rotaNova: semPacote ? null : (rotaNova == null ? this.rotaNova : rotaNova()),
    emergenciasNovas: semPacote ? const [] : (emergenciasNovas ?? this.emergenciasNovas),
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
    final verificacao = Timer.periodic(intervaloDaRota, (_) => unawaited(verificarNovidades()));
    ref.onDispose(() {
      verificacao.cancel();
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

  /// Em jornada, a rota é conferida (só o ETag, sem baixar de novo) a cada 2 min: uma reotimização publicada pelo
  /// programador chega sem o agente precisar puxar a tela.
  static const intervaloDaRota = Duration(minutes: 2);

  /// Id da notificação do Android da nova ordem (a seguinte substitui a anterior).
  static const avisoDaRotaNova = 7302;

  /// Id da notificação da OS emergencial nova (ADR 0051).
  static const avisoDeEmergencial = 7303;

  /// Avisos de chegada feitos nesta sessão (o pacote só traz quando a OS muda).
  final _avisosDeChegada = <String, DateTime>{};

  /// ETag da última rota do servidor que o celular tem (a valendo ou a que espera confirmação).
  String? _etagDaRota;

  /// Lê o que está no celular e tenta atualizar pela API (uma vez por sessão; depois, [atualizar]).
  Future<void> carregar() => _carga ??= _carregar();

  Future<void> _carregar() async {
    final guardado = await _armazem.lerPacote();
    final pendente = await _armazem.lerInicioPendente();
    final rota = await _armazem.lerRota();
    final nova = await _armazem.lerRotaNova();
    _doServidor = guardado == null ? null : PacoteDoDia(guardado.pacote);
    _etagDaRota = nova?.etag ?? rota?.etag;
    state = state.copiar(
      carregado: true,
      baixadoEm: guardado?.baixadoEm,
      inicioPendente: () => pendente,
      rota: () => rota == null ? null : RotaDoDia(rota.rota),
      rotaNova: () => nova == null ? null : RotaDoDia(nova.rota),
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
    if (state.emJornada) {
      await _atualizarRota();
      await _enviarConfirmacao();
    }
  });

  /// Baixa a rota só quando mudou (ETag). Sem jornada no servidor (409), fica a que estava. Uma nova ordem
  /// publicada no meio da jornada espera o agente confirmar (ADR 0050) e gera um aviso do Android.
  Future<void> _atualizarRota() async {
    try {
      final r = await ref.read(apiCampoProvider).rota(conhecida: _etagDaRota);
      if (!r.mudou) return;
      _etagDaRota = r.etag;
      final json = r.json;
      if (json == null) {
        await _armazem.guardarRota(null);
        await _armazem.guardarRotaNova(null);
        state = state.copiar(rota: () => null, rotaNova: () => null);
        await _mostrar();
        return;
      }
      final nova = RotaDoDia(json);
      final atual = state.rota;
      if (nova.exigeConfirmacao && nova.confirmadaEm == null && atual != null && atual.id != nova.id) {
        final jaAvisada = state.rotaNova?.id == nova.id;
        await _armazem.guardarRotaNova(json, etag: r.etag);
        state = state.copiar(rotaNova: () => nova);
        await _mostrar();
        if (!jaAvisada) {
          await ref
              .read(aparelhoProvider)
              .avisar(
                id: avisoDaRotaNova,
                titulo: 'Nova ordem das OS',
                texto: 'A rota de hoje foi reorganizada. Abra o app para conferir e confirmar.',
              );
        }
        return;
      }
      await _armazem.guardarRota(json, etag: r.etag);
      await _armazem.guardarRotaNova(null);
      state = state.copiar(rota: () => nova, rotaNova: () => null);
      await _mostrar();
      if (nova.partida case final p?) {
        unawaited(ref.read(temaDoDiaProvider.notifier).informarLocal(p.latitude, p.longitude));
      }
      // Sem rota anterior não há o que comparar: a nova ordem já é a da lista.
      if (nova.exigeConfirmacao && nova.confirmadaEm == null) await _registrarConfirmacao(nova.id);
    } on ErroDaApi catch (e) {
      if (e.celularRevogado) rethrow;
    }
  }

  /// O agente conferiu a nova ordem: passa a valer na lista e no mapa, e a confirmação vai ao servidor (ou fica
  /// guardada até o sinal voltar).
  Future<void> confirmarRotaNova() async {
    final nova = state.rotaNova;
    if (nova == null) return;
    final guardada = await _armazem.lerRotaNova();
    await _armazem.guardarRota(nova.json, etag: guardada?.etag ?? _etagDaRota);
    await _armazem.guardarRotaNova(null);
    state = state.copiar(rota: () => nova, rotaNova: () => null);
    await _mostrar();
    await _registrarConfirmacao(nova.id);
  }

  Future<void> _registrarConfirmacao(String roteirizacaoId) async {
    await _armazem.guardarConfirmacaoPendente((roteirizacaoId: roteirizacaoId, confirmadaEm: _agora()));
    await _enviarConfirmacao();
  }

  /// Envia a confirmação guardada. Sem sinal, fica para a próxima; recusada (rota já substituída), é esquecida.
  Future<void> _enviarConfirmacao() async {
    final pendente = await _armazem.lerConfirmacaoPendente();
    if (pendente == null) return;
    try {
      await ref.read(apiCampoProvider).confirmarRota(pendente.roteirizacaoId, pendente.confirmadaEm);
      await _armazem.guardarConfirmacaoPendente(null);
    } on SemConexao {
      // Vai na próxima atualização.
    } on ErroDaApi catch (e) {
      if (e.celularRevogado) rethrow;
      await _armazem.guardarConfirmacaoPendente(null);
    }
  }

  /// Conferência periódica em jornada (sem marcar ocupado nem mostrar erro): OS novas no pacote (emergencial toca o
  /// alerta), rota nova e confirmação pendente.
  Future<void> verificarNovidades() async {
    if (!ref.mounted || !state.carregado || !state.emJornada || state.ocupado || state.inicioPendente != null) return;
    try {
      final pacote = _doServidor;
      if (pacote != null) {
        await _guardar(
          await ref
              .read(apiCampoProvider)
              .pacote(desde: _deHoje(pacote) ? pacote.versao : null, equipe: pacote.equipeId),
        );
      }
      await _atualizarRota();
      await _enviarConfirmacao();
    } on SemConexao {
      // Sem sinal: segue a ordem que já tem.
    } on ErroDaApi catch (e) {
      if (e.celularRevogado) await ref.read(sessaoProvider.notifier).sessao.revogar();
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
      await _armazem.guardarRotaNova(null);
      await _armazem.guardarEmergenciaisAvisadas(null);
      _etagDaRota = null;
      _doServidor = null;
      state = state.copiar(semPacote: true);
      state = state.copiar(equipes: await ref.read(apiCampoProvider).equipes());
    }, semSinal: () async => state = state.copiar(erro: () => 'Sem sinal: encerre a jornada quando houver conexão.'));
  }

  void dispensarErro() => state = state.copiar(erro: () => null, abrirAjustes: false);

  /// "Estou chegando" (ADR 0052): SMS ao morador de que a equipe chega em cerca de [minutos]. Só com sinal (um aviso
  /// atrasado não serve); devolve o texto para a tela.
  Future<String> avisarChegada(String osId, int minutos) async {
    try {
      final situacao = await ref
          .read(apiCampoProvider)
          .avisarChegada(osId, id: const Uuid().v4(), minutos: minutos, ocorridoEm: _agora());
      if (situacao == 'FALHOU') return 'Não deu para enviar o aviso agora. Tente de novo em instantes.';
      _avisosDeChegada[osId] = _agora();
      await _mostrar();
      return situacao == 'ENVIADO'
          ? 'Morador avisado: chegada em cerca de $minutos min.'
          : 'Aviso registrado. O envio de SMS ainda não está ligado na sua empresa.';
    } on SemConexao {
      return 'Sem sinal: o aviso não foi enviado. Tente quando houver sinal.';
    } on ErroDaApi catch (e) {
      if (e.celularRevogado) {
        await ref.read(sessaoProvider.notifier).sessao.revogar();
        return e.mensagem;
      }
      return e.mensagem;
    }
  }

  /// O agente viu o alerta da emergencial na tela.
  void dispensarEmergencias() => state = state.copiar(emergenciasNovas: const []);

  /// ADR 0051: OS emergencial que entra no pacote durante a jornada toca o alerta (som e vibração do canal
  /// "emergencial") e aparece em destaque na tela Hoje. As que já estavam no primeiro pacote da jornada não tocam.
  Future<void> _verificarEmergenciais(PacoteDoDia pacote) async {
    final abertas = [
      for (final o in pacote.ordens)
        if (o.prioridade == Prioridade.emergencial && o.aberta) o,
    ];
    final avisadas = await _armazem.lerEmergenciaisAvisadas();
    if (avisadas == null) {
      await _armazem.guardarEmergenciaisAvisadas([for (final o in abertas) o.id]);
      return;
    }
    final novas = [
      for (final o in abertas)
        if (!avisadas.contains(o.id)) o,
    ];
    if (novas.isEmpty) return;
    await _armazem.guardarEmergenciaisAvisadas([...avisadas, for (final o in novas) o.id]);
    state = state.copiar(emergenciasNovas: [...state.emergenciasNovas, for (final o in novas) o.id]);
    final primeira = novas.first;
    await ref
        .read(aparelhoProvider)
        .avisar(
          id: avisoDeEmergencial,
          titulo: novas.length == 1 ? 'OS emergencial nova' : '${novas.length} OS emergenciais novas',
          texto: '${primeira.servicoNome} · ${primeira.endereco}',
          canal: CanalDeAviso.emergencial,
        );
  }

  Future<void> _guardar(Map<String, dynamic> resposta) async {
    final atual = _doServidor;
    final novo = atual == null || resposta['diferenca'] != true ? PacoteDoDia(resposta) : atual.aplicar(resposta);
    final agora = _agora();
    await _armazem.guardarPacote(novo.json, agora);
    _doServidor = novo;
    state = state.copiar(baixadoEm: agora);
    await _mostrar();
    if (novo.jornada?.aberta ?? false) await _verificarEmergenciais(novo);
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
    final comAcoes = pacote.comAcoes(acoes).comAvisos(_avisosDeChegada);
    // Nova ordem ainda não confirmada: a lista segue a rota que vale no celular.
    final valendo = state.rota;
    state = state.copiar(
      pacote: state.rotaNova != null && valendo != null ? comAcoes.naOrdem(valendo.ordem) : comAcoes,
    );
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
