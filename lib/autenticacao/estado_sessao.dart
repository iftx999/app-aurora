/// Onde o agente está na entrada do app (doc 10, 10.9.1 e 10.9.6).
sealed class EstadoSessao {
  const EstadoSessao();
}

class Carregando extends EstadoSessao {
  const Carregando();
}

/// Primeiro uso: falta o código da empresa (o realm do Keycloak).
class SemEmpresa extends EstadoSessao {
  const SemEmpresa();
}

/// Precisa entrar com a conta da empresa (com sinal).
class SemLogin extends EstadoSessao {
  const SemLogin({required this.codigoEmpresa, this.aviso});

  final String codigoEmpresa;

  /// Por que voltou para cá (PIN errado demais, sessão expirada, saiu).
  final String? aviso;
}

/// Logado, ainda sem PIN.
class CriarPin extends EstadoSessao {
  const CriarPin({required this.nome});

  final String nome;
}

/// Tem sessão e PIN: pede o PIN (ou a biometria) para abrir.
class Bloqueada extends EstadoSessao {
  const Bloqueada({required this.nome, required this.tentativasRestantes, required this.biometria, this.erro});

  final String nome;
  final int tentativasRestantes;
  final bool biometria;
  final String? erro;
}

class Desbloqueada extends EstadoSessao {
  const Desbloqueada({required this.nome});

  final String nome;
}

/// O administrador bloqueou o celular (J13): dados locais apagados.
class Revogada extends EstadoSessao {
  const Revogada();
}
