/// Endereços e parâmetros do app, definidos na compilação (`--dart-define`), nunca no código: cada ambiente da
/// empresa gera o seu APK. Os padrões servem ao emulador Android falando com o ambiente local (10.0.2.2 = máquina
/// hospedeira).
class Configuracao {
  const Configuracao({
    required this.api,
    required this.identidade,
    this.clienteId = 'aurora-campo',
    this.redirecionamento = 'dev.aurora.campo:/oauthredirect',
    this.semRedeMaxima = const Duration(days: 7),
    this.permitirHttp = false,
  });

  factory Configuracao.doAmbiente() {
    const api = String.fromEnvironment('AURORA_API', defaultValue: 'http://10.0.2.2:8080');
    const identidade = String.fromEnvironment('AURORA_IDENTIDADE', defaultValue: 'http://10.0.2.2:8180');
    return Configuracao(
      api: Uri.parse(api),
      identidade: Uri.parse(identidade),
      permitirHttp: api.startsWith('http://') || identidade.startsWith('http://'),
    );
  }

  /// API da Aurora (sem barra no fim).
  final Uri api;

  /// Keycloak; o realm é o código da empresa (ADR 0027).
  final Uri identidade;

  /// Cliente público com PKCE no realm da empresa.
  final String clienteId;

  final String redirecionamento;

  /// Sem contato com o Keycloak por mais que isso, o app exige login com sinal (doc 10, 10.9.6).
  final Duration semRedeMaxima;

  /// Só no ambiente local de desenvolvimento.
  final bool permitirHttp;

  Uri emissor(String codigoEmpresa) => Uri.parse('${identidade.toString().replaceAll(RegExp(r'/$'), '')}/realms/$codigoEmpresa');
}
