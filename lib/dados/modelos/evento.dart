import 'dia.dart';

/// Ação registrada no celular (10.9.3; `AcaoDeCampo` no back-end).
enum AcaoDeCampo {
  iniciar('INICIAR'),
  paralisar('PARALISAR'),
  retomar('RETOMAR'),
  devolver('DEVOLVER'),
  encerrar('ENCERRAR');

  const AcaoDeCampo(this.codigo);

  final String codigo;

  static AcaoDeCampo de(String codigo) => values.firstWhere((a) => a.codigo == codigo);

  /// Situação da OS depois da ação, ou nulo se ela não é permitida a partir de [atual] (a mesma regra do servidor).
  StatusOrdem? destino(StatusOrdem atual) => switch (this) {
    iniciar when atual == StatusOrdem.programada => StatusOrdem.emExecucao,
    retomar when atual == StatusOrdem.paralisada => StatusOrdem.emExecucao,
    paralisar when atual == StatusOrdem.emExecucao => StatusOrdem.paralisada,
    encerrar when atual == StatusOrdem.emExecucao => StatusOrdem.encerrada,
    devolver when const {StatusOrdem.programada, StatusOrdem.emExecucao, StatusOrdem.paralisada}.contains(atual) =>
      StatusOrdem.devolvida,
    _ => null,
  };

  String get rotulo => switch (this) {
    iniciar => 'Início',
    paralisar => 'Paralisação',
    retomar => 'Retomada',
    devolver => 'Devolução',
    encerrar => 'Encerramento',
  };
}

/// Evento da fila local: o que o agente fez, guardado **antes** de mudar a tela (10.9.3).
class EventoDeCampo {
  const EventoDeCampo({
    required this.id,
    required this.osId,
    required this.sequencia,
    required this.acao,
    required this.ocorridoEm,
    this.motivoId,
    this.observacao,
    this.resultado,
    this.quantidade,
    this.valores,
    this.posicao,
    this.versaoPacote,
    this.fotos = const [],
  });

  factory EventoDeCampo.deJson(Map<String, dynamic> j) => EventoDeCampo(
    id: j['id'] as String,
    osId: j['osId'] as String,
    sequencia: (j['sequencia'] as num).toInt(),
    acao: AcaoDeCampo.de(j['tipo'] as String),
    ocorridoEm: DateTime.parse(j['ocorridoEm'] as String),
    motivoId: j['motivoId'] as String?,
    observacao: j['observacao'] as String?,
    resultado: j['resultado'] as String?,
    quantidade: j['quantidade'] as num?,
    valores: j['valores'] as Map<String, dynamic>?,
    posicao: j['posicao'] as Map<String, dynamic>?,
    versaoPacote: (j['versaoPacote'] as num?)?.toInt(),
    fotos: (j['fotos'] as List?)?.cast<String>() ?? const [],
  );

  final String id;
  final String osId;

  /// Por OS, contínua a partir da última que o servidor processou.
  final int sequencia;
  final AcaoDeCampo acao;
  final DateTime ocorridoEm;
  final String? motivoId;
  final String? observacao;

  /// No encerramento: EXECUTADA ou NAO_EXECUTADA.
  final String? resultado;
  final num? quantidade;
  final Map<String, dynamic>? valores;
  final Map<String, dynamic>? posicao;
  final int? versaoPacote;

  /// Ids das fotos tiradas na ação (fora do encerramento, cujas fotos vão nos [valores]; ADR 0053).
  final List<String> fotos;

  Map<String, Object?> paraJson() => {
    'id': id,
    'osId': osId,
    'sequencia': sequencia,
    'tipo': acao.codigo,
    'ocorridoEm': ocorridoEm.toUtc().toIso8601String(),
    'motivoId': ?motivoId,
    'observacao': ?observacao,
    'resultado': ?resultado,
    'quantidade': ?quantidade,
    'valores': ?valores,
    'posicao': ?posicao,
    'versaoPacote': ?versaoPacote,
    if (fotos.isNotEmpty) 'fotos': fotos,
  };
}

/// O que aconteceu com o evento: ainda no celular ou a resposta do servidor (RN-26; `SituacaoEvento`).
enum SituacaoDoEnvio {
  pendente,
  aplicado,
  repetido,
  conflito,
  superado,
  aguardando,
  rejeitado;

  static SituacaoDoEnvio de(String s) => switch (s) {
    'APLICADO' => aplicado,
    'REPETIDO' => repetido,
    'CONFLITO' => conflito,
    'SUPERADO' => superado,
    'AGUARDANDO' => aguardando,
    _ => rejeitado,
  };

  /// O servidor já guardou o evento (mesmo o que espera o anterior): sai da fila de envio.
  bool get recebido => this != pendente;

  /// O que o agente fez continua valendo na tela até o pacote do servidor mostrar o resultado.
  bool get valeNoCelular => this != rejeitado && this != superado;

  /// Precisa avisar o agente.
  bool get avisar => this == rejeitado || this == superado || this == conflito;
}

class EventoNaFila {
  const EventoNaFila(
    this.evento, {
    this.situacao = SituacaoDoEnvio.pendente,
    this.mensagem,
    this.respondidoEm,
    this.tentativas = 0,
  });

  final EventoDeCampo evento;
  final SituacaoDoEnvio situacao;
  final String? mensagem;
  final DateTime? respondidoEm;
  final int tentativas;
}

/// Resposta do servidor para um evento do lote.
class RespostaDoEvento {
  const RespostaDoEvento({required this.id, required this.situacao, this.mensagem, this.avisos = const []});

  factory RespostaDoEvento.deJson(Map<String, dynamic> j) {
    final situacao = SituacaoDoEnvio.de(j['situacao'] as String);
    // No REPETIDO, vale a situação da primeira vez.
    final original = j['original'] as String?;
    return RespostaDoEvento(
      id: j['id'] as String,
      situacao: situacao == SituacaoDoEnvio.repetido && original != null ? SituacaoDoEnvio.de(original) : situacao,
      mensagem: j['mensagem'] as String?,
      avisos: (j['avisos'] as List? ?? const []).cast<String>(),
    );
  }

  final String id;
  final SituacaoDoEnvio situacao;
  final String? mensagem;
  final List<String> avisos;
}
