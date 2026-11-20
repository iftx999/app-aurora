import 'dart:async';

import '../dados/api/api_campo.dart';
import '../dados/api/erros.dart';
import '../dados/local/arquivos_de_foto.dart';
import '../dados/local/armazem_do_dia.dart';
import '../dados/modelos/evento.dart';
import '../dados/modelos/foto.dart';

/// Como está a fila (J10: "x ações pendentes · último envio hh:mm").
class EstadoDaFila {
  const EstadoDaFila({
    this.pendentes = 0,
    this.ultimoEnvio,
    this.enviando = false,
    this.falhasSeguidas = 0,
    this.proximaTentativa,
    this.problema,
    this.avisos = const [],
    this.versao = 0,
    this.recebimentos = 0,
    this.fotosPendentes = 0,
    this.avisosDeFoto = const [],
    this.posicoesPendentes = 0,
    this.ultimoEnvioDePosicoes,
  });

  final int pendentes;

  /// Último envio que o servidor respondeu.
  final DateTime? ultimoEnvio;
  final bool enviando;
  final int falhasSeguidas;
  final DateTime? proximaTentativa;

  /// Por que o envio parou sem ser falta de sinal (sessão, servidor recusou o lote).
  final String? problema;

  /// Respostas que o agente precisa ver (recusado, superado, conflito), ainda não mostradas.
  final List<EventoNaFila> avisos;

  /// Muda a cada mudança da fila (para quem mostra a situação das OS por cima do pacote).
  final int versao;

  /// Quantos envios o servidor já recebeu nesta abertura (quem mostra o dia baixa as mudanças do pacote).
  final int recebimentos;

  final int fotosPendentes;

  /// Fotos que o servidor recusou (o texto vai para o agente).
  final List<String> avisosDeFoto;

  /// Posições da jornada ainda no celular (RN-27); não contam como ações do agente.
  final int posicoesPendentes;
  final DateTime? ultimoEnvioDePosicoes;

  /// Nenhuma ação nem foto esperando envio (as posições saem sozinhas e não prendem o fim da jornada).
  bool get vazia => pendentes == 0 && fotosPendentes == 0;
}

/// Envia a fila em lotes, na ordem em que as ações foram feitas, com novas tentativas em intervalos crescentes
/// (10.9.3). Uma chamada por vez; quem chama durante um envio espera o mesmo envio.
class Sincronizador {
  Sincronizador({
    required this.armazem,
    required this.api,
    required this.arquivos,
    DateTime Function()? agora,
    this.aoMudar,
    this.aoRevogar,
    this.aoReceber,
    this.esperas = const [
      Duration(seconds: 5),
      Duration(seconds: 15),
      Duration(seconds: 30),
      Duration(minutes: 1),
      Duration(minutes: 2),
      Duration(minutes: 5),
    ],
    this.tamanhoDoLote = 200,
    this.parteDaFoto = 1024 * 1024,
    this.loteDePosicoes = 500,
    this.posicoesParaEnviar = 5,
    this.guardaDePosicoes = const Duration(days: 7),
  }) : _agora = agora ?? DateTime.now {
    _desde = _agora();
  }

  final ArmazemDoDia armazem;
  final ApiCampo api;
  final ArquivosDeFoto arquivos;

  /// Tamanho de cada parte de foto (o servidor aceita até 1 MB).
  final int parteDaFoto;
  final DateTime Function() _agora;
  final List<Duration> esperas;
  final int tamanhoDoLote;

  /// Até 500 por envio (limite do servidor).
  final int loteDePosicoes;

  /// A partir de quantas posições na fila uma leitura nova dispara o envio (cerca de 10 min de jornada).
  final int posicoesParaEnviar;

  /// Posições mais velhas que isso saem do celular sem envio (o servidor só guarda as da jornada).
  final Duration guardaDePosicoes;

  /// Falso enquanto o início da jornada não chegou ao servidor: as posições esperam (senão iriam para a jornada
  /// anterior e seriam descartadas).
  bool Function() podeEnviarPosicoes = _sempre;

  static bool _sempre() => true;

  void Function(EstadoDaFila)? aoMudar;

  /// O servidor disse que o celular foi bloqueado; chamado depois de enviar o que havia.
  Future<void> Function()? aoRevogar;

  /// Algum evento foi recebido pelo servidor (quem mostra o dia baixa as mudanças do pacote).
  void Function()? aoReceber;

  EstadoDaFila _estado = const EstadoDaFila();
  EstadoDaFila get estado => _estado;

  Future<void>? _emAndamento;
  Timer? _agendado;
  bool _parado = false;
  bool _revogacaoTratada = false;
  late final DateTime _desde;
  final _avisados = <String>{};

  void _mudar(EstadoDaFila novo) {
    _estado = novo;
    aoMudar?.call(novo);
  }

  EstadoDaFila _com({
    int? pendentes,
    DateTime? ultimoEnvio,
    bool? enviando,
    int? falhasSeguidas,
    DateTime? Function()? proximaTentativa,
    String? Function()? problema,
    List<EventoNaFila>? avisos,
    int? recebimentos,
    int? fotosPendentes,
    List<String>? avisosDeFoto,
    int? posicoesPendentes,
    DateTime? ultimoEnvioDePosicoes,
  }) => EstadoDaFila(
    pendentes: pendentes ?? _estado.pendentes,
    ultimoEnvio: ultimoEnvio ?? _estado.ultimoEnvio,
    enviando: enviando ?? _estado.enviando,
    falhasSeguidas: falhasSeguidas ?? _estado.falhasSeguidas,
    proximaTentativa: proximaTentativa == null ? _estado.proximaTentativa : proximaTentativa(),
    problema: problema == null ? _estado.problema : problema(),
    avisos: avisos ?? _estado.avisos,
    versao: _estado.versao + 1,
    recebimentos: recebimentos ?? _estado.recebimentos,
    fotosPendentes: fotosPendentes ?? _estado.fotosPendentes,
    avisosDeFoto: avisosDeFoto ?? _estado.avisosDeFoto,
    posicoesPendentes: posicoesPendentes ?? _estado.posicoesPendentes,
    ultimoEnvioDePosicoes: ultimoEnvioDePosicoes ?? _estado.ultimoEnvioDePosicoes,
  );

  /// Relê a contagem do banco (abertura do app, evento novo).
  Future<void> recontar() async {
    final pendentes = (await armazem.eventos(soPendentes: true)).length;
    final fotos = (await armazem.fotos(soPendentes: true)).length;
    _mudar(_com(pendentes: pendentes, fotosPendentes: fotos, posicoesPendentes: await armazem.contarPosicoes()));
  }

  /// Guarda o evento (com as fotos que ele referencia) e tenta enviar logo (sem esperar o envio).
  Future<void> registrar(EventoDeCampo evento, {List<FotoDaOs> fotos = const []}) async {
    await armazem.registrarEvento(evento, fotos: fotos);
    await recontar();
    unawaited(enviar());
  }

  /// Guarda a leitura do GPS da jornada; com algumas acumuladas, envia (se não estiver esperando o sinal voltar).
  Future<void> registrarPosicao(AmostraDePosicao amostra) async {
    await armazem.guardarPosicao(amostra);
    final n = await armazem.contarPosicoes();
    _mudar(_com(posicoesPendentes: n));
    final esperandoSinal = _agendado?.isActive ?? false;
    if (n >= posicoesParaEnviar && !esperandoSinal && _emAndamento == null) unawaited(enviar());
  }

  /// "Enviar agora": cancela a espera e envia o que houver.
  Future<void> enviar() {
    if (_parado) return Future.value();
    return _emAndamento ??= _enviar().whenComplete(() => _emAndamento = null);
  }

  /// O agente já viu esses avisos.
  void dispensarAvisos() {
    _avisados.addAll(_estado.avisos.map((e) => e.evento.id));
    _mudar(_com(avisos: const [], avisosDeFoto: const []));
  }

  /// Revogação ou troca de empresa: envia o que der e para, sem avisar a revogação de novo.
  Future<void> enviarEParar() async {
    _revogacaoTratada = true;
    if (!_parado) await enviar();
    parar();
  }

  /// Para os envios automáticos (sessão encerrada).
  void parar() {
    _parado = true;
    _agendado?.cancel();
  }

  Future<void> _enviar() async {
    _agendado?.cancel();
    _mudar(_com(enviando: true, proximaTentativa: () => null, problema: () => null));
    var revogado = false;
    var recebeu = false;
    try {
      while (!_parado) {
        final lote = await armazem.eventos(soPendentes: true, limite: tamanhoDoLote);
        if (lote.isEmpty) break;
        final r = await _enviarLote(lote.map((e) => e.evento).toList());
        if (r == null) break;
        recebeu = true;
        revogado = revogado || r;
        _mudar(_com(ultimoEnvio: _agora(), falhasSeguidas: 0));
      }
      // Fotos depois dos eventos (10.9.3); celular revogado não envia mais nada além dos eventos.
      if (!_parado && !revogado && await _enviarFotos()) {
        _mudar(_com(ultimoEnvio: _agora(), falhasSeguidas: 0));
      }
      // Posições por último: são as que menos importam se o sinal cair no meio.
      if (!_parado && !revogado && podeEnviarPosicoes()) await _enviarPosicoes();
    } on SemConexao {
      final falhas = _estado.falhasSeguidas + 1;
      final espera = esperas[(falhas - 1).clamp(0, esperas.length - 1)];
      _mudar(_com(falhasSeguidas: falhas, proximaTentativa: () => _agora().add(espera)));
      if (!_parado) _agendado = Timer(espera, () => unawaited(enviar()));
    } on ErroDaApi catch (e) {
      if (e.celularRevogado) {
        revogado = true;
      } else {
        _mudar(_com(problema: () => e.mensagem));
      }
    } finally {
      await _depoisDoEnvio();
    }
    if (recebeu) {
      _mudar(_com(recebimentos: _estado.recebimentos + 1));
      aoReceber?.call();
    }
    if (revogado && !_revogacaoTratada) {
      _revogacaoTratada = true;
      parar();
      await aoRevogar?.call();
    }
  }

  /// Envia um lote e marca as respostas; devolve se o celular foi revogado, ou nulo se não deu para continuar.
  /// Lote que o servidor nem aceita ler (400) é reenviado um a um, para recusar só o evento com problema.
  Future<bool?> _enviarLote(List<EventoDeCampo> lote) async {
    try {
      await armazem.contarTentativa(lote.map((e) => e.id));
      final r = await api.enviarEventos(lote, _agora());
      await armazem.marcarRespostas(r.respostas, _agora());
      return r.revogado;
    } on ErroDaApi catch (e) {
      if (e.celularRevogado || (e.status != 400 && e.status != 422)) rethrow;
      if (lote.length == 1) {
        await armazem.marcarRecusado(lote.single.id, e.mensagem, _agora());
        return false;
      }
      var revogado = false;
      for (final evento in lote) {
        revogado = (await _enviarLote([evento]) ?? false) || revogado;
      }
      return revogado;
    }
  }

  /// Envia as fotos pendentes, uma a uma, retomando de onde cada uma parou. Devolve se alguma parte chegou.
  Future<bool> _enviarFotos() async {
    var chegou = false;
    // Foto de encerramento que não valeu (recusado ou superado) não tem para onde ir.
    final semEfeito = {
      for (final e in await armazem.eventos())
        if (!e.situacao.valeNoCelular)
          for (final v in (e.evento.valores ?? const {}).values)
            if (v is List) ...v.whereType<String>(),
    };
    for (final foto in await armazem.fotos(soPendentes: true)) {
      if (_parado) break;
      if (semEfeito.contains(foto.id)) {
        await arquivos.apagar(foto.caminho);
        await armazem.esquecerFoto(foto.id);
        continue;
      }
      var atual = foto;
      if (atual.recebido > 0) {
        // Já começou antes: pergunta ao servidor até onde chegou (a última parte pode ter chegado sem resposta).
        atual = _comServidor(atual, await api.estadoDaFoto(atual.id));
      }
      var conflitos = 0;
      while (atual.situacao == SituacaoDaFoto.pendente) {
        final fim = (atual.recebido + parteDaFoto).clamp(0, atual.tamanho);
        try {
          final bytes = await arquivos.ler(atual.caminho, atual.recebido, fim);
          atual = _comServidor(atual, await api.enviarParteDaFoto(atual, atual.recebido, bytes));
          chegou = true;
        } on ErroDaApi catch (e) {
          if (e.celularRevogado) rethrow;
          if (e.status == 409 && conflitos++ < 3) {
            // O servidor está em outro ponto do arquivo: retoma de lá.
            atual = _comServidor(atual, await api.estadoDaFoto(atual.id));
          } else if (const {400, 403, 404, 409, 413, 415, 422}.contains(e.status)) {
            // 404/403: a OS não está mais com a equipe da pessoa.
            atual = atual.com(situacao: SituacaoDaFoto.recusada, recusa: e.mensagem);
          } else {
            rethrow;
          }
        }
        await armazem.atualizarFoto(atual);
      }
      if (atual.situacao == SituacaoDaFoto.recusada) {
        _mudar(_com(avisosDeFoto: [..._estado.avisosDeFoto, 'Foto recusada: ${atual.recusa ?? 'arquivo inválido'}.']));
      }
      // Enviada ou recusada: o arquivo sai do celular.
      await arquivos.apagar(atual.caminho);
      await armazem.esquecerFoto(atual.id);
    }
    return chegou;
  }

  /// Envia as posições em lotes; qualquer resposta do servidor tira o lote do celular (gravadas ou fora da jornada).
  Future<void> _enviarPosicoes() async {
    while (!_parado) {
      final lote = await armazem.posicoes(limite: loteDePosicoes);
      if (lote.isEmpty) return;
      try {
        await api.enviarPosicoes([for (final p in lote) p.amostra]);
      } on ErroDaApi catch (e) {
        // 409: nenhuma jornada da equipe no servidor; 400/422: leitura que o servidor não aceita. Nos dois casos,
        // reenviar não adianta. Outros erros (servidor fora) tentam de novo depois.
        if (e.celularRevogado || !const {400, 409, 422}.contains(e.status)) rethrow;
      }
      await armazem.esquecerPosicoes(lote.last.ordem);
      _mudar(_com(posicoesPendentes: await armazem.contarPosicoes(), ultimoEnvioDePosicoes: _agora()));
    }
  }

  static FotoDaOs _comServidor(FotoDaOs foto, AnexoNoServidor? servidor) => switch (servidor?.situacao) {
    null => foto.com(recebido: 0),
    'DISPONIVEL' => foto.com(situacao: SituacaoDaFoto.enviada, recebido: foto.tamanho),
    'RECUSADO' => foto.com(situacao: SituacaoDaFoto.recusada, recusa: servidor!.recusa),
    _ => foto.com(recebido: servidor!.recebido),
  };

  Future<void> _depoisDoEnvio() async {
    // Respondidos há mais de 2 dias saem do celular.
    await armazem.esquecerRespondidos(_agora().subtract(const Duration(days: 2)));
    await armazem.esquecerPosicoesAntigas(_agora().subtract(guardaDePosicoes));
    final todos = await armazem.eventos();
    // Só o que chegou nesta abertura do app; o histórico fica na tela da fila.
    final avisos = todos
        .where(
          (e) => e.situacao.avisar && !_avisados.contains(e.evento.id) && !(e.respondidoEm?.isBefore(_desde) ?? true),
        )
        .toList();
    _mudar(
      _com(
        enviando: false,
        pendentes: todos.where((e) => e.situacao == SituacaoDoEnvio.pendente).length,
        fotosPendentes: (await armazem.fotos(soPendentes: true)).length,
        posicoesPendentes: await armazem.contarPosicoes(),
        avisos: avisos,
      ),
    );
  }
}
