import 'package:aurora_campo/dados/api/api_campo.dart';
import 'package:aurora_campo/dados/api/cliente_api.dart';
import 'package:aurora_campo/dados/api/erros.dart';
import 'package:aurora_campo/dados/localizacao.dart';
import 'package:aurora_campo/dados/modelos/dia.dart';

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
};

Map<String, dynamic> pacoteJson({
  String equipe = equipeRede,
  String nome = 'Equipe Rede Centro',
  int versao = 100,
  bool diferenca = false,
  List<Map<String, dynamic>>? ordens,
  List<String>? ids,
  bool jornadaAberta = true,
  DateTime? gerado,
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
    'parametros': {
      'v1': [
        {'chave': 'obs', 'rotulo': 'Observação', 'tipo': 'TEXTO', 'obrigatorio': false},
      ],
    },
    'motivos': [
      {'id': 'm1', 'tipo': 'PARALISACAO', 'codigo': 'CHUVA', 'nome': 'Chuva forte', 'exigeObservacao': false},
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
