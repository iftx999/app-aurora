import 'dart:async';

import 'package:aurora_campo/dados/aparelho.dart';
import 'package:aurora_campo/dados/api/api_campo.dart';
import 'package:aurora_campo/dados/api/cliente_api.dart';
import 'package:aurora_campo/dados/api/erros.dart';
import 'package:aurora_campo/dados/localizacao.dart';
import 'package:aurora_campo/dados/modelos/dia.dart';
import 'package:aurora_campo/dados/modelos/evento.dart';
import 'package:aurora_campo/dados/modelos/foto.dart';
import 'package:aurora_campo/dados/camera.dart';

/// Quarta, 18/11/2026, 09:00 (hora local).
final agoraDosTestes = DateTime(2026, 11, 18, 9);

const equipeRede = 'e1000000-0000-0000-0000-000000000001';
const equipeLigacoes = 'e2000000-0000-0000-0000-000000000002';

Map<String, dynamic> ordemJson(
  String id, {
  int? sequencia,
  String status = 'PROGRAMADA',
  String prioridade = 'MEDIA',
  String servico = 'Religação',
  String rua = 'R. XV de Novembro',
  String numero = '410',
  DateTime? atualizada,
  int ultimaSequencia = 0,
  bool avisoDeChegada = false,
  List<String>? fasesComFoto,
}) => {
  'ordem': {
    'id': id,
    'numero': 1000 + id.hashCode % 1000,
    'servicoNome': servico,
    'unidadeMedida': 'un',
    'alvo': 'IMOVEL',
    'logradouroNome': rua,
    'numeroImovel': numero,
    'prioridade': prioridade,
    'status': status,
    'prazoEm': DateTime.utc(2026, 11, 18, 20).toIso8601String(),
    'quantidadePrevista': 1,
    'atrasada': false,
    'latitude': -22.56,
    'longitude': -47.40,
    'sequenciaRota': sequencia,
  },
  'servicoVersaoId': 'v1',
  'ultimaSequencia': ultimaSequencia,
  'avisoDeChegada': avisoDeChegada,
  'fasesComFoto': ?fasesComFoto,
};

EventoDeCampo eventoDeTeste(String id, {String os = 'a', int sequencia = 1, AcaoDeCampo acao = AcaoDeCampo.iniciar}) =>
    EventoDeCampo(id: id, osId: os, sequencia: sequencia, acao: acao, ocorridoEm: agoraDosTestes);

Map<String, dynamic> pacoteJson({
  String equipe = equipeRede,
  String nome = 'Equipe Rede Centro',
  int versao = 100,
  bool diferenca = false,
  List<Map<String, dynamic>>? ordens,
  List<String>? ids,
  bool jornadaAberta = true,
  DateTime? gerado,
  List<Map<String, dynamic>>? parametros,
}) {
  final lista =
      ordens ??
      [
        ordemJson('a', sequencia: 2),
        ordemJson('b', sequencia: 1, servico: 'Vistoria de viabilidade', status: 'ENCERRADA'),
        ordemJson('c', sequencia: 3, servico: 'Desobstrução de ramal', prioridade: 'EMERGENCIAL'),
      ];
  return {
    'versao': versao,
    'diferenca': diferenca,
    'equipeId': equipe,
    'equipeNome': nome,
    'jornada': jornadaAberta
        ? {
            'id': 'j1',
            'equipeId': equipe,
            'equipeNome': nome,
            'inicio': DateTime.utc(2026, 11, 18, 10, 12).toIso8601String(),
            'fim': null,
          }
        : null,
    'ids': ids ?? [for (final o in lista) (o['ordem'] as Map)['id']],
    'ordens': lista,
    // Como o servidor: a diferença só traz os parâmetros das versões das OS alteradas.
    'parametros': {
      if (!diferenca || parametros != null || lista.isNotEmpty)
        'v1':
            parametros ??
            [
              {'chave': 'obs', 'rotulo': 'Observação', 'tipo': 'TEXTO', 'obrigatorio': false},
            ],
    },
    'motivos': [
      {'id': 'm1', 'tipo': 'PARALISACAO', 'codigo': 'CHUVA', 'nome': 'Chuva forte', 'exigeObservacao': false},
      {'id': 'm2', 'tipo': 'PARALISACAO', 'codigo': 'OUTRO', 'nome': 'Outro', 'exigeObservacao': true},
      {
        'id': 'm3',
        'tipo': 'DEVOLUCAO',
        'codigo': 'ENDERECO',
        'nome': 'Endereço não encontrado',
        'exigeObservacao': false,
      },
      {
        'id': 'm4',
        'tipo': 'NAO_EXECUCAO',
        'codigo': 'SEM_INTERESSE',
        'nome': 'Morador sem interesse',
        'exigeObservacao': false,
      },
    ],
    'raioInicioM': 150,
    'geradoEm': (gerado ?? agoraDosTestes).toUtc().toIso8601String(),
  };
}

/// API de campo em memória: [semSinal] simula falta de rede.
class ApiFalsa extends ApiCampo {
  ApiFalsa({this.revogado = false, List<EquipeDoDia>? equipes})
    : equipesDoDia = equipes ?? const [],
      super(
        ClienteApi(base: Uri.parse('http://api'), credenciais: _SemCredenciais()),
        () async => const InfoDoAparelho(modelo: 'Teste', sistema: 'Android 15', versaoApp: '1.0.0+1'),
      );

  final bool revogado;
  List<EquipeDoDia> equipesDoDia;
  bool semSinal = false;
  int cadastros = 0;
  final inicios = <Map<String, Object?>>[];
  final pedidosDePacote = <({int? desde, String? equipe})>[];
  int encerramentos = 0;

  /// Respostas de `GET /jornada`, na ordem; a última se repete.
  final respostasDoPacote = <Map<String, dynamic>>[];

  /// Resposta de `POST /jornada/inicio`.
  Map<String, dynamic> Function(String equipe) aoIniciar = (equipe) => pacoteJson(equipe: equipe);

  /// Lotes recebidos em `POST /eventos`.
  final lotes = <List<EventoDeCampo>>[];

  /// Resposta por evento (padrão: aplicado). Lançar [ErroDaApi] recusa o lote inteiro.
  RespostaDoEvento Function(EventoDeCampo) responder = (e) =>
      RespostaDoEvento(id: e.id, situacao: SituacaoDoEnvio.aplicado);
  bool revogarNoEnvio = false;
  int confirmacoesDeApagado = 0;

  @override
  Future<({List<RespostaDoEvento> respostas, bool revogado})> enviarEventos(
    List<EventoDeCampo> eventos,
    DateTime enviadoEm,
  ) async {
    _rede();
    final respostas = [for (final e in eventos) responder(e)];
    lotes.add(eventos);
    return (respostas: respostas, revogado: revogarNoEnvio);
  }

  /// Rota publicada (`GET /campo/rota`); nula = 204. [pedidosDeRota] guarda o ETag de cada pedido.
  Map<String, dynamic>? rotaPublicada;
  final pedidosDeRota = <String?>[];
  ErroDaApi? erroNaRota;

  @override
  Future<({bool mudou, Map<String, dynamic>? json, String? etag})> rota({String? conhecida}) async {
    _rede();
    pedidosDeRota.add(conhecida);
    if (erroNaRota case final e?) throw e;
    final r = rotaPublicada;
    final etag = r == null ? null : '"${r['roteirizacaoId']}"';
    if (etag != null && etag == conhecida) return (mudou: false, json: null, etag: conhecida);
    return (mudou: true, json: r, etag: etag);
  }

  /// Avisos de chegada recebidos; [situacaoDoAviso] é a resposta e [erroNoAviso] é lançado no lugar dela.
  final avisosDeChegada = <({String os, int minutos})>[];
  String situacaoDoAviso = 'ENVIADO';
  Object? erroNoAviso;

  @override
  Future<String> avisarChegada(
    String osId, {
    required String id,
    required int minutos,
    required DateTime ocorridoEm,
  }) async {
    _rede();
    if (erroNoAviso case final e?) throw e;
    avisosDeChegada.add((os: osId, minutos: minutos));
    return situacaoDoAviso;
  }

  /// Confirmações recebidas em `POST /rota/confirmacao`; [erroNaConfirmacao] é lançado no lugar da resposta.
  final confirmacoesDeRota = <({String id, DateTime em})>[];
  Object? erroNaConfirmacao;

  @override
  Future<void> confirmarRota(String roteirizacaoId, DateTime confirmadaEm) async {
    _rede();
    if (erroNaConfirmacao case final e?) throw e;
    confirmacoesDeRota.add((id: roteirizacaoId, em: confirmadaEm));
  }

  /// Lotes recebidos em `POST /posicoes`; [erroNasPosicoes] é lançado no lugar da resposta.
  final lotesDePosicoes = <List<AmostraDePosicao>>[];
  ErroDaApi? erroNasPosicoes;

  @override
  Future<int> enviarPosicoes(List<AmostraDePosicao> amostras) async {
    _rede();
    if (erroNasPosicoes case final e?) throw e;
    lotesDePosicoes.add(amostras);
    return amostras.length;
  }

  @override
  Future<void> confirmarApagado() async {
    _rede();
    confirmacoesDeApagado++;
  }

  /// Fotos no "servidor": id → bytes recebidos; [recusarFoto] devolve RECUSADO no fim.
  final fotosRecebidas = <String, List<int>>{};
  final partes = <({String id, int inicio, int tamanho})>[];
  bool recusarFoto = false;

  /// Perde a resposta desta parte (o servidor recebeu, o celular não soube).
  int? perderRespostaDaParte;

  @override
  Future<AnexoNoServidor?> estadoDaFoto(String id) async {
    _rede();
    final b = fotosRecebidas[id];
    return b == null ? null : AnexoNoServidor(recebido: b.length, situacao: 'RECEBENDO');
  }

  @override
  Future<AnexoNoServidor> enviarParteDaFoto(FotoDaOs foto, int inicio, List<int> bytes) async {
    _rede();
    final atual = fotosRecebidas[foto.id] ?? <int>[];
    if (inicio != atual.length) throw const ErroDaApi(409, 'Parte fora de ordem.');
    fotosRecebidas[foto.id] = [...atual, ...bytes];
    partes.add((id: foto.id, inicio: inicio, tamanho: bytes.length));
    if (perderRespostaDaParte == partes.length) throw const SemConexao('resposta perdida');
    final recebido = fotosRecebidas[foto.id]!.length;
    if (recebido < foto.tamanho) return AnexoNoServidor(recebido: recebido, situacao: 'RECEBENDO');
    return recusarFoto
        ? AnexoNoServidor(recebido: recebido, situacao: 'RECUSADO', recusa: 'o conteúdo não é image/jpeg')
        : AnexoNoServidor(recebido: recebido, situacao: 'DISPONIVEL');
  }

  void _rede() {
    if (semSinal) throw const SemConexao('teste');
  }

  @override
  Future<void> cadastrarCelular() async {
    cadastros++;
    if (revogado) {
      throw const ErroDaApi(403, 'Bloqueado', codigo: 'DISPOSITIVO_REVOGADO');
    }
  }

  @override
  Future<List<EquipeDoDia>> equipes() async {
    _rede();
    return equipesDoDia;
  }

  @override
  Future<Map<String, dynamic>> pacote({int? desde, String? equipe}) async {
    _rede();
    pedidosDePacote.add((desde: desde, equipe: equipe));
    return respostasDoPacote.length > 1 ? respostasDoPacote.removeAt(0) : respostasDoPacote.first;
  }

  @override
  Future<Map<String, dynamic>> iniciarJornada({
    required String id,
    required String equipeId,
    required DateTime ocorridoEm,
    required Posicao posicao,
  }) async {
    _rede();
    inicios.add({'id': id, 'equipeId': equipeId, 'ocorridoEm': ocorridoEm, 'latitude': posicao.latitude});
    return aoIniciar(equipeId);
  }

  @override
  Future<void> encerrarJornada(DateTime ocorridoEm) async {
    _rede();
    encerramentos++;
  }
}

class _SemCredenciais implements Credenciais {
  @override
  Future<String> dispositivoId() async => 'd';

  @override
  Future<String> tokenDeAcesso() async => 't';
}

class GpsFalso implements Localizacao {
  GpsIndisponivel? falha;
  int leituras = 0;

  @override
  Future<Posicao> atual() async {
    leituras++;
    if (falha case final f?) throw f;
    return const Posicao(-22.5645, -47.4017, precisaoM: 6);
  }

  @override
  Future<void> abrirAjustes() async {}
}

const equipesDeTeste = [
  EquipeDoDia(
    id: equipeRede,
    nome: 'Equipe Rede Centro',
    ordensHoje: 3,
    emergenciais: 1,
    veiculoNome: 'Caminhão hidrojato',
  ),
  EquipeDoDia(
    id: equipeLigacoes,
    nome: 'Equipe Ligações Norte',
    ordensHoje: 2,
    emergenciais: 0,
    veiculoNome: 'Caminhonete',
  ),
];

class CameraFalsa implements Camera {
  int fotos = 0;

  @override
  Future<String?> tirar() async => '/cache/foto${++fotos}.jpg';
}

/// GPS contínuo controlado pelo teste: [ler] entrega uma leitura, [falhar] simula GPS desligado.
class PosicoesFalsas implements FonteDePosicoes {
  final assinaturas = <bool>[];
  StreamController<AmostraDePosicao>? _atual;

  bool get ativa => _atual != null && !_atual!.isClosed && _atual!.hasListener;

  @override
  Stream<AmostraDePosicao> acompanhar({required bool economia}) {
    assinaturas.add(economia);
    final c = StreamController<AmostraDePosicao>();
    c.onCancel = c.close;
    _atual = c;
    return c.stream;
  }

  void ler(DateTime momento, double latitude, double longitude, {double precisaoM = 8}) =>
      _atual?.add(AmostraDePosicao(momento, Posicao(latitude, longitude, precisaoM: precisaoM)));

  void falhar(GpsIndisponivel erro) => _atual?.addError(erro);
}

class AparelhoFalso implements Aparelho {
  ({int nivel, bool carregando})? carga = (nivel: 80, carregando: false);
  int pedidosDeNotificacao = 0;
  final avisos = <({int id, String titulo, String texto, CanalDeAviso canal})>[];

  @override
  Future<void> avisar({
    required int id,
    required String titulo,
    required String texto,
    CanalDeAviso canal = CanalDeAviso.rota,
  }) async => avisos.add((id: id, titulo: titulo, texto: texto, canal: canal));

  @override
  Future<({int nivel, bool carregando})?> bateria() async => carga;

  @override
  Future<bool> pedirNotificacoes() async {
    pedidosDeNotificacao++;
    return true;
  }
}

/// Rota como o servidor devolve: três paradas a/b/c a leste da partida, pela malha.
Map<String, dynamic> rotaJson({
  String id = 'r1',
  String origem = 'JORNADA',
  bool pelaMalha = true,
  List<String> ordem = const ['b', 'a', 'c'],
  bool exigeConfirmacao = false,
}) => {
  'roteirizacaoId': id,
  'origem': origem,
  'exigeConfirmacao': exigeConfirmacao,
  'confirmadaEm': null,
  'calculo': pelaMalha ? 'VALHALLA' : 'LINHA_RETA',
  'publicadaEm': agoraDosTestes.toUtc().toIso8601String(),
  'inicio': agoraDosTestes.toUtc().toIso8601String(),
  'fimPrevisto': DateTime.utc(2026, 11, 18, 18, 40).toIso8601String(),
  'km': 12.4,
  'minutosDeslocamento': 38,
  'minutosServico': 120,
  'partidaLatitude': -22.5645,
  'partidaLongitude': -47.4017,
  'tracado': pelaMalha
      ? [
          [
            [-47.4017, -22.5645],
            [-47.4000, -22.5640],
            [-47.40, -22.56],
          ],
        ]
      : const [],
  'paradas': [
    for (final (i, os) in ordem.indexed)
      {
        'ordemServicoId': os,
        'ordem': i + 1,
        'chegadaPrevista': agoraDosTestes.add(Duration(minutes: 30 * (i + 1))).toUtc().toIso8601String(),
        'saidaPrevista': agoraDosTestes.add(Duration(minutes: 30 * (i + 1) + 20)).toUtc().toIso8601String(),
        'latitude': -22.56,
        'longitude': -47.40 + i * 0.001,
      },
  ],
};
