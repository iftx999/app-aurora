/// Foto de um parâmetro do encerramento (10.9.3): tirada e reduzida no celular, guardada na pasta privada do app e
/// enviada em partes depois dos eventos; o evento de encerramento a referencia pelo [id].
library;

enum SituacaoDaFoto { pendente, enviada, recusada }

class FotoDaOs {
  const FotoDaOs({
    required this.id,
    required this.osId,
    required this.parametro,
    required this.caminho,
    required this.tipoMidia,
    required this.tamanho,
    required this.sha256,
    required this.tiradaEm,
    this.situacao = SituacaoDaFoto.pendente,
    this.recebido = 0,
    this.recusa,
  });

  final String id;
  final String osId;

  /// Chave do parâmetro de foto.
  final String parametro;

  /// Arquivo na pasta privada do app.
  final String caminho;
  final String tipoMidia;
  final int tamanho;

  /// SHA-256 do arquivo inteiro, em hexadecimal (o servidor confere no fim).
  final String sha256;
  final DateTime tiradaEm;
  final SituacaoDaFoto situacao;

  /// Bytes que o servidor já confirmou (para retomar de onde parou).
  final int recebido;
  final String? recusa;

  FotoDaOs com({SituacaoDaFoto? situacao, int? recebido, String? recusa}) => FotoDaOs(
    id: id,
    osId: osId,
    parametro: parametro,
    caminho: caminho,
    tipoMidia: tipoMidia,
    tamanho: tamanho,
    sha256: sha256,
    tiradaEm: tiradaEm,
    situacao: situacao ?? this.situacao,
    recebido: recebido ?? this.recebido,
    recusa: recusa ?? this.recusa,
  );
}

/// O que o servidor tem da foto (`AnexoResponse`).
class AnexoNoServidor {
  const AnexoNoServidor({required this.recebido, required this.situacao, this.recusa});

  factory AnexoNoServidor.deJson(Map<String, dynamic> j) => AnexoNoServidor(
    recebido: (j['recebido'] as num).toInt(),
    situacao: j['situacao'] as String,
    recusa: j['recusa'] as String?,
  );

  final int recebido;

  /// RECEBENDO, DISPONIVEL ou RECUSADO.
  final String situacao;
  final String? recusa;
}
