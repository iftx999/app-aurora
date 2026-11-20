/// Fundo do mapa (tiles raster) e a atribuição exigida pelo provedor.
class FundoDoMapa {
  const FundoDoMapa({required this.tiles, required this.atribuicao, this.zoomMaximo = 19});

  /// Modelo com {z}/{x}/{y}.
  final String tiles;
  final String atribuicao;
  final int zoomMaximo;
}

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
    this.mapa = osm,
    this.empresaGerenciada,
  });

  /// Tiles públicos do OpenStreetMap: só para desenvolvimento (a política de uso não admite tráfego de produção). A
  /// empresa informa o provedor contratado ou o servidor de tiles próprio na compilação, como no front web (ADR 0017).
  static const osm = FundoDoMapa(
    tiles: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    atribuicao: '© OpenStreetMap',
  );

  /// Valores da compilação (`--dart-define`), substituídos pelos da configuração gerenciada do Android Enterprise
  /// ([gerenciada], chaves de `res/xml/app_restrictions.xml`) quando o MDM os define: um só APK para todas as empresas.
  /// Endereço gerenciado só vale com HTTPS (HTTP só no build de desenvolvimento).
  factory Configuracao.doAmbiente({Map<String, Object?> gerenciada = const {}}) {
    const apiCompilada = String.fromEnvironment('AURORA_API', defaultValue: 'http://10.0.2.2:8080');
    const identidadeCompilada = String.fromEnvironment('AURORA_IDENTIDADE', defaultValue: 'http://10.0.2.2:8180');
    final httpNaCompilacao = apiCompilada.startsWith('http://') || identidadeCompilada.startsWith('http://');
    String? endereco(String chave) {
      final v = (gerenciada[chave] as String?)?.trim() ?? '';
      final uri = Uri.tryParse(v);
      final valido =
          uri != null && uri.hasAuthority && (uri.scheme == 'https' || (httpNaCompilacao && uri.scheme == 'http'));
      return valido ? v : null;
    }

    final api = endereco('api_url') ?? apiCompilada;
    final identidade = endereco('identidade_url') ?? identidadeCompilada;
    final codigo = (gerenciada['codigo_empresa'] as String?)?.trim().toLowerCase() ?? '';
    final tiles = (gerenciada['mapa_tiles'] as String?)?.trim() ?? '';
    final tilesValidos =
        tiles.startsWith('https://') && tiles.contains('{z}') && tiles.contains('{x}') && tiles.contains('{y}');
    final atribuicao = (gerenciada['mapa_atribuicao'] as String?)?.trim() ?? '';
    return Configuracao(
      api: Uri.parse(api),
      identidade: Uri.parse(identidade),
      permitirHttp: api.startsWith('http://') || identidade.startsWith('http://'),
      empresaGerenciada: codigoDeEmpresaValido(codigo) ? codigo : null,
      mapa: tilesValidos
          ? FundoDoMapa(tiles: tiles, atribuicao: atribuicao.isEmpty ? '© Provedor do mapa' : atribuicao)
          : const bool.hasEnvironment('AURORA_MAPA_TILES')
          ? const FundoDoMapa(
              tiles: String.fromEnvironment('AURORA_MAPA_TILES'),
              atribuicao: String.fromEnvironment('AURORA_MAPA_ATRIBUICAO'),
              zoomMaximo: int.fromEnvironment('AURORA_MAPA_ZOOM_MAXIMO', defaultValue: 19),
            )
          : osm,
    );
  }

  static bool codigoDeEmpresaValido(String codigo) => RegExp(r'^[a-z0-9][a-z0-9-]{1,39}$').hasMatch(codigo);

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

  final FundoDoMapa mapa;

  /// Código da empresa fixado pelo MDM: o app não pergunta nem deixa trocar.
  final String? empresaGerenciada;

  Uri emissor(String codigoEmpresa) =>
      Uri.parse('${identidade.toString().replaceAll(RegExp(r'/$'), '')}/realms/$codigoEmpresa');
}
