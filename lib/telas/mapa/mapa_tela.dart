import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../app/dependencias.dart';
import '../../app/tema.dart';
import '../../dados/api/api_campo.dart';
import '../../dados/modelos/dia.dart';
import '../../dados/modelos/rota.dart';
import '../../jornada/coleta_de_posicoes.dart';
import '../../jornada/controle_do_dia.dart';
import '../../nucleo/datas.dart';
import '../ordem/ordem_tela.dart';

void abrirMapa(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const MapaTela()));

LatLng _ponto(Posicao p) => LatLng(p.latitude, p.longitude);

/// Mapa da rota do dia (J8; ADR 0048): traçado pela malha (ou linha reta, rotulada como estimativa), as OS numeradas
/// na ordem da rota e a posição do agente. Tocar numa parada abre a OS.
class MapaTela extends ConsumerWidget {
  const MapaTela({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dia = ref.watch(controleDoDiaProvider);
    final posicao = ref.watch(coletaProvider.select((c) => c.posicao));
    final mapa = ref.watch(configuracaoProvider).mapa;
    final c = context.cores;
    final rota = dia.rota;
    final ordens = dia.pacote?.ordens ?? const <OrdemDoDia>[];
    final comLocal = [
      for (final o in ordens)
        if (o.latitude != null && o.longitude != null) o,
    ];
    final voce = posicao ?? rota?.partida;
    final pontos = [
      for (final o in comLocal) LatLng(o.latitude!, o.longitude!),
      if (voce != null) _ponto(voce),
      for (final l in rota?.tracado ?? const <List<Posicao>>[]) ...l.map(_ponto),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Mapa da rota')),
      body: Column(
        children: [
          Expanded(
            child: pontos.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Nenhuma OS de hoje tem localização no mapa.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: c.textoSecundario),
                      ),
                    ),
                  )
                : FlutterMap(
                    options: MapOptions(
                      initialCameraFit: pontos.length == 1
                          ? null
                          : CameraFit.coordinates(coordinates: pontos, padding: const EdgeInsets.all(48)),
                      initialCenter: pontos.first,
                      initialZoom: 15,
                      maxZoom: mapa.zoomMaximo.toDouble(),
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                      ),
                    ),
                    children: [
                      // Sem modelo de tiles (testes, ou empresa sem provedor): só a rota e as paradas.
                      if (mapa.tiles.isNotEmpty)
                        TileLayer(urlTemplate: mapa.tiles, userAgentPackageName: 'dev.aurora.campo'),
                      PolylineLayer(polylines: _linhas(rota, ordens, voce, c)),
                      MarkerLayer(
                        markers: [
                          if (voce != null)
                            Marker(
                              point: _ponto(voce),
                              width: 28,
                              height: 28,
                              child: Semantics(
                                label: 'Você',
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: c.destaque,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: c.superficie, width: 4),
                                  ),
                                ),
                              ),
                            ),
                          for (final o in comLocal)
                            Marker(
                              point: LatLng(o.latitude!, o.longitude!),
                              width: 48,
                              height: 48,
                              child: _Parada(ordem: o, numero: _numero(dia.pacote!, o)),
                            ),
                        ],
                      ),
                      RichAttributionWidget(
                        alignment: AttributionAlignment.bottomLeft,
                        attributions: [TextSourceAttribution(mapa.atribuicao)],
                      ),
                    ],
                  ),
          ),
          _Resumo(rota: rota, semLocal: ordens.length - comLocal.length),
        ],
      ),
    );
  }

  static int _numero(PacoteDoDia p, OrdemDoDia o) => o.sequencia ?? (p.ordens.indexOf(o) + 1);

  /// Pela malha: o traçado. Sem ele: segmentos retos tracejados da posição pelas OS abertas, na ordem da rota.
  static List<Polyline> _linhas(RotaDoDia? rota, List<OrdemDoDia> ordens, Posicao? voce, CoresAurora c) {
    final tracado = rota?.tracado ?? const <List<Posicao>>[];
    if (tracado.isNotEmpty) {
      return [
        for (final linha in tracado)
          Polyline(
            points: linha.map(_ponto).toList(),
            strokeWidth: 5,
            color: c.destaque,
            borderStrokeWidth: 2,
            borderColor: c.superficie,
          ),
      ];
    }
    final reta = [
      if (voce != null) _ponto(voce),
      for (final o in ordens)
        if (o.aberta && o.latitude != null && o.longitude != null) LatLng(o.latitude!, o.longitude!),
    ];
    return reta.length < 2
        ? const []
        : [
            Polyline(
              points: reta,
              strokeWidth: 3,
              color: c.neutro,
              pattern: StrokePattern.dashed(segments: const [10, 8]),
            ),
          ];
  }
}

/// Número da parada, na cor da situação; abre a OS.
class _Parada extends StatelessWidget {
  const _Parada({required this.ordem, required this.numero});

  final OrdemDoDia ordem;
  final int numero;

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    final fundo = !ordem.aberta
        ? c.neutro
        : ordem.prioridade == Prioridade.emergencial
        ? c.perigo
        : (ordem.status == StatusOrdem.emExecucao ? c.ok : c.destaque);
    return Semantics(
      button: true,
      label: 'Parada $numero, ${ordem.servicoNome}, ${ordem.endereco}',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () => abrirOrdem(context, ordem),
        child: Center(
          child: Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: fundo,
              shape: BoxShape.circle,
              border: Border.all(color: c.superficie, width: 3),
            ),
            child: Text(
              '$numero',
              style: TextStyle(color: ordem.aberta ? c.sobreDestaque : c.fundo, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ),
    );
  }
}

/// "12,4 km · 38 min de deslocamento · fim previsto 15:40", sempre como estimativa (RN-25).
class _Resumo extends StatelessWidget {
  const _Resumo({required this.rota, required this.semLocal});

  final RotaDoDia? rota;
  final int semLocal;

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    final texto = Theme.of(context).textTheme;
    final r = rota;
    final linhas = [
      if (r == null)
        'Rota ainda não calculada: a lista segue a ordem da programação.'
      else ...[
        '${r.km.toStringAsFixed(1).replaceAll('.', ',')} km · ${r.minutosDeslocamento} min de deslocamento · '
            'fim previsto ${hora(r.fimPrevisto)}',
        [
          r.origem == 'JORNADA' ? 'Calculada da sua posição no início' : 'Calculada pelo programador',
          r.pelaMalha ? 'pelas ruas' : 'em linha reta',
          'estimativa',
        ].join(' · '),
      ],
      if (semLocal > 0) semLocal == 1 ? '1 OS sem localização no mapa' : '$semLocal OS sem localização no mapa',
    ];
    return Material(
      color: c.superficie,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(linhas.first, style: texto.titleSmall),
              for (final l in linhas.skip(1)) Text(l, style: TextStyle(color: c.textoSecundario)),
            ],
          ),
        ),
      ),
    );
  }
}
