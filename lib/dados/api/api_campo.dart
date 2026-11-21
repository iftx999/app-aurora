import '../modelos/dia.dart';
import '../modelos/evento.dart';
import '../modelos/foto.dart';
import 'erros.dart';
import 'cliente_api.dart';

/// Modelo, sistema e versão do app, enviados no cadastro do celular (J13).
class InfoDoAparelho {
  const InfoDoAparelho({required this.modelo, required this.sistema, required this.versaoApp});

  final String modelo;
  final String sistema;
  final String versaoApp;
}

/// Posição lida do GPS.
class Posicao {
  const Posicao(this.latitude, this.longitude, {this.precisaoM});

  final double latitude;
  final double longitude;
  final double? precisaoM;

  Map<String, Object?> paraJson() => {'latitude': latitude, 'longitude': longitude, 'precisaoM': precisaoM};
}

/// Posição da jornada com a hora da leitura (RN-27).
class AmostraDePosicao {
  const AmostraDePosicao(this.momento, this.posicao);

  final DateTime momento;
  final Posicao posicao;

  Map<String, Object?> paraJson() => {'momento': momento.toUtc().toIso8601String(), ...posicao.paraJson()};
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

  /// J8: equipes da pessoa com o resumo de hoje.
  Future<List<EquipeDoDia>> equipes() async =>
      (await _cliente.getLista('/api/v1/campo/equipes'))
          .map((e) => EquipeDoDia.deJson(e as Map<String, dynamic>))
          .toList();

  /// Pacote do dia (10.9.2); com [desde], só as OS alteradas. A resposta crua vai para [PacoteDoDia.aplicar].
  Future<Map<String, dynamic>> pacote({int? desde, String? equipe}) =>
      _cliente.get('/api/v1/campo/jornada', parametros: {if (desde != null) 'desde': '$desde', 'equipe': ?equipe});

  /// J8: abre a jornada (idempotente pelo [id] gerado no celular) e devolve o pacote completo.
  Future<Map<String, dynamic>> iniciarJornada({
    required String id,
    required String equipeId,
    required DateTime ocorridoEm,
    required Posicao posicao,
  }) => _cliente.post('/api/v1/campo/jornada/inicio', {
    'id': id,
    'equipeId': equipeId,
    'ocorridoEm': ocorridoEm.toUtc().toIso8601String(),
    'posicao': posicao.paraJson(),
  });

  Future<void> encerrarJornada(DateTime ocorridoEm) =>
      _cliente.postSemResposta('/api/v1/campo/jornada/fim', {'ocorridoEm': ocorridoEm.toUtc().toIso8601String()});

  /// Lote de eventos da fila, em ordem (até 200; 10.9.4). [revogado]: o celular foi bloqueado e deve apagar os dados.
  Future<({List<RespostaDoEvento> respostas, bool revogado})> enviarEventos(
    List<EventoDeCampo> eventos,
    DateTime enviadoEm,
  ) async {
    final r = await _cliente.post('/api/v1/campo/eventos', {
      'enviadoEm': enviadoEm.toUtc().toIso8601String(),
      'eventos': [for (final e in eventos) e.paraJson()],
    });
    return (
      respostas: [for (final e in r['eventos'] as List) RespostaDoEvento.deJson(e as Map<String, dynamic>)],
      revogado: r['revogado'] as bool? ?? false,
    );
  }

  /// Posições da jornada em lote (até 500, em qualquer ordem); devolve quantas o servidor gravou.
  /// 409: não há jornada aberta no servidor.
  Future<int> enviarPosicoes(List<AmostraDePosicao> amostras) async {
    final r = await _cliente.post('/api/v1/campo/posicoes', {
      'posicoes': [for (final a in amostras) a.paraJson()],
    });
    return (r['gravadas'] as num?)?.toInt() ?? 0;
  }

  /// Rota publicada da equipe em jornada (ADR 0048). [conhecida]: ETag da rota que o celular já tem.
  /// Devolve `mudou: false` quando é a mesma (304); `json` nulo quando não há rota publicada (204).
  Future<({bool mudou, Map<String, dynamic>? json, String? etag})> rota({String? conhecida}) async {
    final r = await _cliente.getCondicional('/api/v1/campo/rota', etag: conhecida);
    return switch (r.status) {
      304 => (mudou: false, json: null, etag: conhecida),
      200 => (mudou: true, json: r.json, etag: r.etag),
      _ => (mudou: true, json: null, etag: null),
    };
  }

  /// "Estou chegando" (ADR 0052): SMS ao morador. Devolve a situação: ENVIADO, REGISTRADO (sem provedor de SMS na
  /// empresa) ou FALHOU (tentar de novo, com outro [id]).
  Future<String> avisarChegada(
    String osId, {
    required String id,
    required int minutos,
    required DateTime ocorridoEm,
  }) async {
    final r = await _cliente.post('/api/v1/campo/ordens/$osId/aviso-de-chegada', {
      'id': id,
      'minutos': minutos,
      'ocorridoEm': ocorridoEm.toUtc().toIso8601String(),
    });
    return r['situacao'] as String;
  }

  /// ADR 0050: o agente conferiu e confirmou a nova ordem das OS (repetir não muda a primeira confirmação).
  Future<void> confirmarRota(String roteirizacaoId, DateTime confirmadaEm) => _cliente.postSemResposta(
    '/api/v1/campo/rota/confirmacao',
    {'roteirizacaoId': roteirizacaoId, 'confirmadaEm': confirmadaEm.toUtc().toIso8601String()},
  );

  /// Quanto da foto o servidor já tem; nulo se nada chegou ainda.
  Future<AnexoNoServidor?> estadoDaFoto(String id) async {
    try {
      return AnexoNoServidor.deJson(await _cliente.get('/api/v1/campo/anexos/$id'));
    } on ErroDaApi catch (e) {
      if (e.status == 404) return null;
      rethrow;
    }
  }

  /// Uma parte da foto, de [inicio] em diante (até 1 MB; 10.9.3).
  Future<AnexoNoServidor> enviarParteDaFoto(FotoDaOs foto, int inicio, List<int> bytes) async => AnexoNoServidor.deJson(
    await _cliente.putBytes(
      '/api/v1/campo/anexos/${foto.id}',
      bytes,
      parametros: {'os': foto.osId, 'parametro': foto.parametro},
      cabecalhos: {
        'Content-Type': foto.tipoMidia,
        'Content-Range': 'bytes $inicio-${inicio + bytes.length - 1}/${foto.tamanho}',
        'X-Conteudo-Sha256': foto.sha256,
      },
    ),
  );
}
