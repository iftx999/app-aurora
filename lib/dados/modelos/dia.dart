/// Dados do dia como a API de campo manda (`/api/v1/campo`, ADR 0045). Guardam o JSON original para o
/// armazenamento local e para aplicar as diferenças do pacote (10.9.2).
library;

enum StatusOrdem {
  planejada('PLANEJADA'),
  programada('PROGRAMADA'),
  emExecucao('EM_EXECUCAO'),
  paralisada('PARALISADA'),
  devolvida('DEVOLVIDA'),
  encerrada('ENCERRADA'),
  cancelada('CANCELADA');

  const StatusOrdem(this.codigo);

  final String codigo;
}

enum Prioridade { emergencial, alta, media, baixa }

StatusOrdem _status(String s) =>
    StatusOrdem.values.firstWhere((v) => v.codigo == s, orElse: () => StatusOrdem.cancelada);

Prioridade _prioridade(String s) => switch (s) {
  'EMERGENCIAL' => Prioridade.emergencial,
  'ALTA' => Prioridade.alta,
  'BAIXA' => Prioridade.baixa,
  _ => Prioridade.media,
};

DateTime? _data(Object? v) => v == null ? null : DateTime.parse(v as String);

/// Equipe da pessoa com o resumo de hoje, para escolher com qual sai (J8).
class EquipeDoDia {
  const EquipeDoDia({
    required this.id,
    required this.nome,
    required this.ordensHoje,
    required this.emergenciais,
    this.veiculoNome,
    this.jornadaAberta = false,
  });

  factory EquipeDoDia.deJson(Map<String, dynamic> j) => EquipeDoDia(
    id: j['id'] as String,
    nome: j['nome'] as String,
    ordensHoje: (j['ordensHoje'] as num).toInt(),
    emergenciais: (j['emergenciais'] as num).toInt(),
    veiculoNome: j['veiculoNome'] as String?,
    jornadaAberta: j['jornadaAberta'] as bool? ?? false,
  );

  final String id;
  final String nome;
  final int ordensHoje;
  final int emergenciais;
  final String? veiculoNome;

  /// Alguém da equipe já iniciou: quem iniciar agora entra na mesma jornada.
  final bool jornadaAberta;

  String get resumo => [
    ordensHoje == 0 ? 'nenhuma OS hoje' : '$ordensHoje OS hoje',
    if (emergenciais > 0) '$emergenciais ${emergenciais == 1 ? 'emergencial' : 'emergenciais'}',
    ?veiculoNome,
    if (jornadaAberta) 'jornada já iniciada',
  ].join(' · ');
}

class Jornada {
  const Jornada({required this.id, required this.equipeId, required this.equipeNome, required this.inicio, this.fim});

  factory Jornada.deJson(Map<String, dynamic> j) => Jornada(
    id: j['id'] as String,
    equipeId: j['equipeId'] as String,
    equipeNome: j['equipeNome'] as String,
    inicio: DateTime.parse(j['inicio'] as String),
    fim: _data(j['fim']),
  );

  final String id;
  final String equipeId;
  final String equipeNome;
  final DateTime inicio;
  final DateTime? fim;

  bool get aberta => fim == null;
}

/// OS do pacote, com o que o app mostra e usa na execução.
class OrdemDoDia {
  const OrdemDoDia(this.json, {required this.servicoVersaoId, this.ultimaSequencia = 0});

  factory OrdemDoDia.deJson(Map<String, dynamic> j) => OrdemDoDia(
    j['ordem'] as Map<String, dynamic>,
    servicoVersaoId: j['servicoVersaoId'] as String,
    ultimaSequencia: (j['ultimaSequencia'] as num?)?.toInt() ?? 0,
  );

  final Map<String, dynamic> json;
  final String servicoVersaoId;

  /// Último evento do campo que o servidor já processou nesta OS.
  final int ultimaSequencia;

  /// A mesma OS com a situação que o celular já registrou e o servidor ainda não mostrou.
  OrdemDoDia comStatus(StatusOrdem novo) =>
      OrdemDoDia({...json, 'status': novo.codigo}, servicoVersaoId: servicoVersaoId, ultimaSequencia: ultimaSequencia);

  String get id => json['id'] as String;
  int get numero => (json['numero'] as num).toInt();
  String get servicoNome => json['servicoNome'] as String;
  String get unidadeMedida => json['unidadeMedida'] as String;
  bool get noTrecho => json['alvo'] == 'TRECHO';
  String? get matricula => json['matricula'] as String?;
  String? get trechoCodigo => json['trechoCodigo'] as String?;
  String? get logradouro => json['logradouroNome'] as String?;
  String? get numeroImovel => json['numeroImovel'] as String?;
  String? get complemento => json['complemento'] as String?;
  String? get instrucoes => json['instrucoes'] as String?;
  num get quantidadePrevista => json['quantidadePrevista'] as num;
  Prioridade get prioridade => _prioridade(json['prioridade'] as String);
  StatusOrdem get status => _status(json['status'] as String);
  DateTime get prazo => DateTime.parse(json['prazoEm'] as String);
  bool get atrasada => json['atrasada'] as bool? ?? false;
  double? get latitude => (json['latitude'] as num?)?.toDouble();
  double? get longitude => (json['longitude'] as num?)?.toDouble();

  /// Posição na rota do dia (J6, J7); sem rota, nulo.
  int? get sequencia => (json['sequenciaRota'] as num?)?.toInt();

  bool get aberta => const {StatusOrdem.programada, StatusOrdem.emExecucao, StatusOrdem.paralisada}.contains(status);

  /// "R. das Palmeiras, 120 · ap 2" ou "R. Sete de Setembro · trecho T-14".
  String get endereco {
    final rua = logradouro ?? '';
    if (noTrecho) {
      return [if (rua.isNotEmpty) rua, if (trechoCodigo != null) 'trecho $trechoCodigo'].join(' · ');
    }
    final base = numeroImovel == null ? rua : '$rua, $numeroImovel';
    return [if (base.isNotEmpty) base, ?complemento].join(' · ');
  }
}

/// Parâmetro de encerramento da versão do serviço (J2).
class ParametroDoServico {
  const ParametroDoServico(this.json);

  final Map<String, dynamic> json;

  String get chave => json['chave'] as String;
  String get rotulo => json['rotulo'] as String;
  String get tipo => json['tipo'] as String;
  bool get obrigatorio => json['obrigatorio'] as bool? ?? false;
}

class MotivoDoCampo {
  const MotivoDoCampo(this.json);

  final Map<String, dynamic> json;

  String get id => json['id'] as String;

  /// PARALISACAO, DEVOLUCAO ou NAO_EXECUCAO.
  String get tipo => json['tipo'] as String;
  String get nome => json['nome'] as String;
  bool get exigeObservacao => json['exigeObservacao'] as bool? ?? false;
  String? get servicoId => json['servicoId'] as String?;
}

/// Pacote do dia da equipe (10.9.2). [json] é sempre o pacote completo (com as diferenças já aplicadas).
class PacoteDoDia {
  PacoteDoDia(this.json)
    : ordens = (json['ordens'] as List).map((o) => OrdemDoDia.deJson(o as Map<String, dynamic>)).toList()
        ..sort(_naRota);

  factory PacoteDoDia.deJson(Map<String, dynamic> json) => PacoteDoDia(json);

  PacoteDoDia._(this.json, this.ordens);

  /// O pacote como a tela mostra: a situação do servidor com as ações do celular por cima, na ordem em que foram
  /// feitas, enquanto o pacote não as reflete. [json] continua o do servidor.
  PacoteDoDia comAcoes(Iterable<({String osId, StatusOrdem? Function(StatusOrdem) destino})> acoes) {
    final porId = {for (final o in ordens) o.id: o};
    for (final a in acoes) {
      final o = porId[a.osId];
      final novo = o == null ? null : a.destino(o.status);
      if (o != null && novo != null) porId[a.osId] = o.comStatus(novo);
    }
    return PacoteDoDia._(json, [for (final o in ordens) porId[o.id]!]);
  }

  final Map<String, dynamic> json;

  /// Na ordem da rota; as sem posição na rota vão para o fim, por prioridade e prazo.
  final List<OrdemDoDia> ordens;

  int get versao => (json['versao'] as num).toInt();
  String get equipeId => json['equipeId'] as String;
  String get equipeNome => json['equipeNome'] as String;
  Jornada? get jornada => json['jornada'] == null ? null : Jornada.deJson(json['jornada'] as Map<String, dynamic>);
  int get raioInicioM => (json['raioInicioM'] as num).toInt();
  DateTime get geradoEm => DateTime.parse(json['geradoEm'] as String);

  List<ParametroDoServico> parametros(String servicoVersaoId) =>
      ((json['parametros'] as Map<String, dynamic>)[servicoVersaoId] as List? ?? const [])
          .map((p) => ParametroDoServico(p as Map<String, dynamic>))
          .toList();

  List<MotivoDoCampo> get motivos =>
      (json['motivos'] as List).map((m) => MotivoDoCampo(m as Map<String, dynamic>)).toList();

  OrdemDoDia? get emExecucao => ordens.where((o) => o.status == StatusOrdem.emExecucao).firstOrNull;

  /// Próxima a fazer: a em execução, ou a primeira aberta na rota.
  OrdemDoDia? get atual => emExecucao ?? ordens.where((o) => o.aberta).firstOrNull;

  int get abertas => ordens.where((o) => o.aberta).length;

  /// Aplica a resposta de `GET /jornada?desde=` (só as OS alteradas): troca as alteradas, remove as que saíram do
  /// pacote e junta os parâmetros das versões novas. Uma resposta completa substitui tudo.
  PacoteDoDia aplicar(Map<String, dynamic> resposta) {
    if (resposta['diferenca'] != true) {
      return PacoteDoDia(resposta);
    }
    final ids = (resposta['ids'] as List).cast<String>().toSet();
    final porId = <String, dynamic>{
      for (final o in json['ordens'] as List) ((o as Map)['ordem'] as Map)['id'] as String: o,
      for (final o in resposta['ordens'] as List) ((o as Map)['ordem'] as Map)['id'] as String: o,
    }..removeWhere((id, _) => !ids.contains(id));
    return PacoteDoDia({
      ...resposta,
      'diferenca': false,
      'ordens': porId.values.toList(),
      'parametros': {...json['parametros'] as Map<String, dynamic>, ...resposta['parametros'] as Map<String, dynamic>},
    });
  }

  static int _naRota(OrdemDoDia a, OrdemDoDia b) {
    final sa = a.sequencia, sb = b.sequencia;
    if (sa != null && sb != null) return sa.compareTo(sb);
    if (sa != null) return -1;
    if (sb != null) return 1;
    final p = a.prioridade.index.compareTo(b.prioridade.index);
    return p != 0 ? p : a.prazo.compareTo(b.prazo);
  }
}
