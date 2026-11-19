import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../app/dependencias.dart';
import '../autenticacao/estado_sessao.dart';
import '../dados/api/api_campo.dart';
import '../dados/api/erros.dart';
import '../dados/local/armazem_do_dia.dart';
import '../dados/localizacao.dart';
import '../dados/modelos/dia.dart';

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

  bool get emJornada => inicioPendente != null || (pacote?.jornada?.aberta ?? false);

  EstadoDoDia copiar({
    bool? carregado,
    List<EquipeDoDia>? equipes,
    PacoteDoDia? pacote,
    DateTime? baixadoEm,
    InicioPendente? Function()? inicioPendente,
    bool? ocupado,
    bool? semSinal,
    String? Function()? erro,
    bool? abrirAjustes,
  }) => EstadoDoDia(
    carregado: carregado ?? this.carregado,
    equipes: equipes ?? this.equipes,
    pacote: pacote ?? this.pacote,
    baixadoEm: baixadoEm ?? this.baixadoEm,
    inicioPendente: inicioPendente == null ? this.inicioPendente : inicioPendente(),
    ocupado: ocupado ?? this.ocupado,
    semSinal: semSinal ?? this.semSinal,
    erro: erro == null ? this.erro : erro(),
    abrirAjustes: abrirAjustes ?? this.abrirAjustes,
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
    if (ref.mounted) super.state = novo;
  }

  ArmazemDoDia get _armazem => ref.read(armazemProvider);
  DateTime _agora() => ref.read(relogioProvider)();

  @override
  EstadoDoDia build() {
    // Saiu, trocou de empresa ou teve o celular revogado: o próximo login começa do zero.
    ref.listen(sessaoProvider, (anterior, novo) {
      final saiu = anterior is Desbloqueada || anterior is Bloqueada;
      if (saiu && (novo is SemLogin || novo is SemEmpresa || novo is Revogada)) ref.invalidateSelf();
    });
    _carga = Future.microtask(_carregar);
    return const EstadoDoDia();
  }

  Future<void>? _carga;

  /// Lê o que está no celular e tenta atualizar pela API (uma vez por sessão; depois, [atualizar]).
  Future<void> carregar() => _carga ??= _carregar();

  Future<void> _carregar() async {
    final guardado = await _armazem.lerPacote();
    final pendente = await _armazem.lerInicioPendente();
    state = state.copiar(
      carregado: true,
      pacote: guardado == null ? null : PacoteDoDia(guardado.pacote),
      baixadoEm: guardado?.baixadoEm,
      inicioPendente: () => pendente,
    );
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
    }
    final equipes = await ref.read(apiCampoProvider).equipes();
    state = state.copiar(equipes: equipes);
    final pacote = state.pacote;
    if (pacote != null && state.emJornada) {
      final resposta = await ref
          .read(apiCampoProvider)
          .pacote(desde: _deHoje(pacote) ? pacote.versao : null, equipe: pacote.equipeId);
      await _guardar(resposta);
    }
  });

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

  /// J8: encerra a jornada; nenhuma OS pode estar em execução.
  Future<void> encerrar() async {
    final pacote = state.pacote;
    if (pacote?.emExecucao != null) {
      state = state.copiar(erro: () => 'Paralise ou encerre a OS em execução antes de encerrar a jornada.');
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
      final atual = state.pacote;
      if (atual != null && atual.jornada != null) {
        final json = {
          ...atual.json,
          'jornada': {...atual.json['jornada'] as Map<String, dynamic>, 'fim': _agora().toUtc().toIso8601String()},
        };
        await _armazem.guardarPacote(json, state.baixadoEm ?? _agora());
        state = state.copiar(pacote: PacoteDoDia(json));
      }
      state = state.copiar(equipes: await ref.read(apiCampoProvider).equipes());
    }, semSinal: () async => state = state.copiar(erro: () => 'Sem sinal: encerre a jornada quando houver conexão.'));
  }

  void dispensarErro() => state = state.copiar(erro: () => null, abrirAjustes: false);

  Future<void> _guardar(Map<String, dynamic> resposta) async {
    final atual = state.pacote;
    final novo = atual == null || resposta['diferenca'] != true ? PacoteDoDia(resposta) : atual.aplicar(resposta);
    final agora = _agora();
    await _armazem.guardarPacote(novo.json, agora);
    state = state.copiar(pacote: novo, baixadoEm: agora);
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
