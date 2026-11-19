/// Erro da API em Problem Details (RFC 9457), com o código da Aurora quando houver.
class ErroDaApi implements Exception {
  const ErroDaApi(this.status, this.mensagem, {this.codigo});

  final int status;
  final String mensagem;
  final String? codigo;

  /// Celular bloqueado pelo administrador (J13).
  bool get celularRevogado => codigo == 'DISPOSITIVO_REVOGADO';

  @override
  String toString() => 'ErroDaApi($status, $codigo): $mensagem';
}

/// Sem rede ou servidor fora do ar: a ação fica na fila (10.9.3).
class SemConexao implements Exception {
  const SemConexao([this.causa]);

  final Object? causa;

  @override
  String toString() => 'SemConexao($causa)';
}
