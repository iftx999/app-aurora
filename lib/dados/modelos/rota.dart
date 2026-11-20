import '../api/api_campo.dart';

/// Parada da rota publicada.
class ParadaDaRota {
  const ParadaDaRota({required this.osId, required this.ordem, required this.chegadaPrevista, this.local});

  final String osId;
  final int ordem;
  final DateTime chegadaPrevista;
  final Posicao? local;
}

/// Rota do dia da equipe (`GET /campo/rota`, ADR 0048): sempre estimativa (RN-25).
class RotaDoDia {
  RotaDoDia(this.json)
    : tracado = [
        for (final linha in json['tracado'] as List? ?? const [])
          [for (final p in linha as List) Posicao(((p as List)[1] as num).toDouble(), (p[0] as num).toDouble())],
      ],
      paradas = [
        for (final p in json['paradas'] as List? ?? const [])
          ParadaDaRota(
            osId: (p as Map<String, dynamic>)['ordemServicoId'] as String,
            ordem: (p['ordem'] as num).toInt(),
            chegadaPrevista: DateTime.parse(p['chegadaPrevista'] as String),
            local: p['latitude'] == null
                ? null
                : Posicao((p['latitude'] as num).toDouble(), (p['longitude'] as num).toDouble()),
          ),
      ];

  final Map<String, dynamic> json;

  /// Linhas pela malha viária; vazio quando calculada em linha reta.
  final List<List<Posicao>> tracado;
  final List<ParadaDaRota> paradas;

  String get id => json['roteirizacaoId'] as String;

  /// JORNADA (calculada da posição do agente), PREVIA ou REOTIMIZACAO (pelo programador).
  String get origem => json['origem'] as String;
  bool get pelaMalha => json['calculo'] == 'VALHALLA';
  double get km => (json['km'] as num).toDouble();
  int get minutosDeslocamento => (json['minutosDeslocamento'] as num).toInt();
  DateTime get fimPrevisto => DateTime.parse(json['fimPrevisto'] as String);

  Posicao? get partida => json['partidaLatitude'] == null
      ? null
      : Posicao((json['partidaLatitude'] as num).toDouble(), (json['partidaLongitude'] as num).toDouble());
}
