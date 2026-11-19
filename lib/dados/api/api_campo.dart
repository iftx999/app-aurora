import 'cliente_api.dart';

/// Modelo, sistema e versão do app, enviados no cadastro do celular (J13).
class InfoDoAparelho {
  const InfoDoAparelho({required this.modelo, required this.sistema, required this.versaoApp});

  final String modelo;
  final String sistema;
  final String versaoApp;
}

/// Endpoints de `/api/v1/campo` (ADR 0045).
class ApiCampo {
  ApiCampo(this._cliente, this._info);

  final ClienteApi _cliente;
  final Future<InfoDoAparelho> Function() _info;

  Future<void> cadastrarCelular() async {
    final info = await _info();
    await _cliente.post('/api/v1/campo/dispositivo', {
      'modelo': info.modelo,
      'sistema': info.sistema,
      'versaoApp': info.versaoApp,
    });
  }

  /// O app apagou os dados locais depois da revogação.
  Future<void> confirmarApagado() => _cliente.postSemResposta('/api/v1/campo/dispositivo/apagado', const {});
}
