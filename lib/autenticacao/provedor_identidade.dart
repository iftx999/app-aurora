import 'dart:convert';

import 'package:flutter_appauth/flutter_appauth.dart';

import '../nucleo/configuracao.dart';

/// Tokens do Keycloak. O de renovação é "offline" (escopo offline_access): vale enquanto o agente fica sem sinal e
/// renova o acesso quando a rede volta.
class Tokens {
  const Tokens({required this.acesso, required this.expiraEm, this.renovacao, this.idToken});

  factory Tokens.deJson(Map<String, dynamic> json) => Tokens(
    acesso: json['acesso'] as String,
    expiraEm: DateTime.parse(json['expiraEm'] as String),
    renovacao: json['renovacao'] as String?,
    idToken: json['idToken'] as String?,
  );

  final String acesso;
  final DateTime expiraEm;
  final String? renovacao;
  final String? idToken;

  Map<String, dynamic> paraJson() => {
    'acesso': acesso,
    'expiraEm': expiraEm.toIso8601String(),
    'renovacao': renovacao,
    'idToken': idToken,
  };

  /// Afirmações do token de acesso (sem validar a assinatura: só para mostrar o nome; quem valida é a API).
  Map<String, dynamic> get afirmacoes {
    final partes = acesso.split('.');
    if (partes.length != 3) {
      return const {};
    }
    try {
      return jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(partes[1])))) as Map<String, dynamic>;
    } on FormatException {
      return const {};
    }
  }

  String get nome => (afirmacoes['given_name'] ?? afirmacoes['name'] ?? afirmacoes['email'] ?? '') as String;
}

/// Login OIDC (Authorization Code + PKCE) no navegador do sistema; o app nunca vê a senha.
abstract interface class ProvedorIdentidade {
  Future<Tokens> entrar(Uri emissor);
  Future<Tokens> renovar(Uri emissor, String renovacao);
  Future<void> sair(Uri emissor, String? idToken);
}

class ProvedorAppAuth implements ProvedorIdentidade {
  ProvedorAppAuth(this._configuracao);

  final Configuracao _configuracao;
  final FlutterAppAuth _appAuth = const FlutterAppAuth();

  static const _escopos = ['openid', 'profile', 'email', 'offline_access'];

  @override
  Future<Tokens> entrar(Uri emissor) async {
    final r = await _appAuth.authorizeAndExchangeCode(
      AuthorizationTokenRequest(
        _configuracao.clienteId,
        _configuracao.redirecionamento,
        issuer: emissor.toString(),
        scopes: _escopos,
        allowInsecureConnections: _configuracao.permitirHttp,
      ),
    );
    return _tokens(r.accessToken, r.accessTokenExpirationDateTime, r.refreshToken, r.idToken);
  }

  @override
  Future<Tokens> renovar(Uri emissor, String renovacao) async {
    final r = await _appAuth.token(
      TokenRequest(
        _configuracao.clienteId,
        _configuracao.redirecionamento,
        issuer: emissor.toString(),
        refreshToken: renovacao,
        scopes: _escopos,
        allowInsecureConnections: _configuracao.permitirHttp,
      ),
    );
    return _tokens(r.accessToken, r.accessTokenExpirationDateTime, r.refreshToken ?? renovacao, r.idToken);
  }

  @override
  Future<void> sair(Uri emissor, String? idToken) async {
    if (idToken == null) {
      return;
    }
    await _appAuth.endSession(
      EndSessionRequest(
        idTokenHint: idToken,
        postLogoutRedirectUrl: _configuracao.redirecionamento,
        issuer: emissor.toString(),
        allowInsecureConnections: _configuracao.permitirHttp,
      ),
    );
  }

  static Tokens _tokens(String? acesso, DateTime? expira, String? renovacao, String? idToken) {
    if (acesso == null) {
      throw StateError('O provedor de identidade não devolveu o token de acesso.');
    }
    return Tokens(
      acesso: acesso,
      expiraEm: expira ?? DateTime.now().add(const Duration(minutes: 5)),
      renovacao: renovacao,
      idToken: idToken,
    );
  }
}
