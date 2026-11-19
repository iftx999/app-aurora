import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'erros.dart';

/// Fornece o token de acesso válido (renovando se preciso) e o identificador do celular.
abstract interface class Credenciais {
  Future<String> tokenDeAcesso();
  Future<String> dispositivoId();
}

/// HTTP da API de campo: token, cabeçalho do celular (`X-Aurora-Dispositivo`), JSON e erros em Problem Details.
class ClienteApi {
  ClienteApi({required this.base, required this.credenciais, http.Client? http_, this.tempoLimite = const Duration(seconds: 20)})
    : _http = http_ ?? http.Client();

  final Uri base;
  final Credenciais credenciais;
  final Duration tempoLimite;
  final http.Client _http;

  Future<Map<String, dynamic>> get(String caminho, {Map<String, String>? parametros}) async =>
      _json(await _enviar('GET', caminho, parametros: parametros));

  Future<Map<String, dynamic>> post(String caminho, Object? corpo) async =>
      _json(await _enviar('POST', caminho, corpo: corpo));

  Future<void> postSemResposta(String caminho, Object? corpo) async {
    await _enviar('POST', caminho, corpo: corpo);
  }

  Future<http.Response> _enviar(String metodo, String caminho, {Object? corpo, Map<String, String>? parametros}) async {
    final uri = base.replace(
      path: '${base.path.replaceAll(RegExp(r'/$'), '')}$caminho',
      queryParameters: parametros,
    );
    final pedido = http.Request(metodo, uri)
      ..headers.addAll({
        'Authorization': 'Bearer ${await credenciais.tokenDeAcesso()}',
        'X-Aurora-Dispositivo': await credenciais.dispositivoId(),
        'Accept': 'application/json',
      });
    if (corpo != null) {
      pedido
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode(corpo);
    }
    final http.Response resposta;
    try {
      resposta = await http.Response.fromStream(await _http.send(pedido).timeout(tempoLimite));
    } on SocketException catch (e) {
      throw SemConexao(e);
    } on TimeoutException catch (e) {
      throw SemConexao(e);
    } on http.ClientException catch (e) {
      throw SemConexao(e);
    }
    if (resposta.statusCode >= 500) {
      throw SemConexao('HTTP ${resposta.statusCode}');
    }
    if (resposta.statusCode >= 400) {
      throw _erro(resposta);
    }
    return resposta;
  }

  static Map<String, dynamic> _json(http.Response r) =>
      r.body.isEmpty ? const {} : jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;

  static ErroDaApi _erro(http.Response r) {
    try {
      final p = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      return ErroDaApi(r.statusCode, (p['detail'] ?? p['title'] ?? 'Erro ${r.statusCode}') as String,
          codigo: p['codigo'] as String?);
    } on FormatException {
      return ErroDaApi(r.statusCode, 'Erro ${r.statusCode}');
    }
  }
}
