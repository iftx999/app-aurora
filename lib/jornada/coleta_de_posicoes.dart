import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/dependencias.dart';
import '../dados/api/api_campo.dart';
import '../dados/localizacao.dart';
import '../sincronizacao/controle_da_fila.dart';
import 'controle_do_dia.dart';

/// Escolhe quais leituras do GPS viram posição da jornada (10.9.3): uma a cada 2 min **ou** a cada 100 m andados,
/// o que vier primeiro; em economia (bateria baixa), 5 min ou 250 m. Leituras imprecisas são descartadas.
class Amostrador {
  Amostrador({
    this.intervalo = const Duration(minutes: 2),
    this.distanciaM = 100,
    this.intervaloEmEconomia = const Duration(minutes: 5),
    this.distanciaEmEconomiaM = 250,
    this.precisaoMaximaM = 150,
  });

  final Duration intervalo;
  final double distanciaM;
  final Duration intervaloEmEconomia;
  final double distanciaEmEconomiaM;
  final double precisaoMaximaM;

  AmostraDePosicao? _ultima;
  AmostraDePosicao? get ultima => _ultima;

  bool aceita(AmostraDePosicao leitura, {bool economia = false}) {
    final precisao = leitura.posicao.precisaoM;
    if (precisao != null && precisao > precisaoMaximaM) return false;
    final ultima = _ultima;
    final aceitar =
        ultima == null ||
        !leitura.momento.difference(ultima.momento).isNegative &&
            (leitura.momento.difference(ultima.momento) >= (economia ? intervaloEmEconomia : intervalo) ||
                distanciaEmMetros(ultima.posicao, leitura.posicao) >= (economia ? distanciaEmEconomiaM : distanciaM));
    if (aceitar) _ultima = leitura;
    return aceitar;
  }

  void recomecar() => _ultima = null;
}

/// Distância na superfície da Terra (haversine), em metros.
double distanciaEmMetros(Posicao a, Posicao b) {
  const raio = 6371000.0;
  double rad(double g) => g * pi / 180;
  final dLat = rad(b.latitude - a.latitude);
  final dLon = rad(b.longitude - a.longitude);
  final h = pow(sin(dLat / 2), 2) + cos(rad(a.latitude)) * cos(rad(b.latitude)) * pow(sin(dLon / 2), 2);
  return 2 * raio * asin(sqrt(h));
}

/// O que a tela mostra da coleta (RN-27: o agente vê quando a localização está sendo registrada).
class EstadoDaColeta {
  const EstadoDaColeta({
    this.ativa = false,
    this.ultima,
    this.posicao,
    this.economia = false,
    this.problema,
    this.abrirAjustes = false,
  });

  final bool ativa;

  /// Última posição guardada.
  final DateTime? ultima;

  /// Onde o agente estava na última leitura aceita (marcador "você" no mapa).
  final Posicao? posicao;
  final bool economia;

  /// GPS desligado ou permissão retirada durante a jornada.
  final String? problema;
  final bool abrirAjustes;
}

final coletaProvider = NotifierProvider<ControleDaColeta, EstadoDaColeta>(ControleDaColeta.new);

/// Liga a coleta quando a jornada abre e desliga quando ela fecha (ou a sessão acaba). As posições vão para a fila
/// do [Sincronizador], que as envia junto com o resto.
class ControleDaColeta extends Notifier<EstadoDaColeta> {
  /// A bateria é conferida de tempos em tempos; abaixo de [bateriaBaixa] e fora da tomada, entra em economia.
  static const bateriaBaixa = 20;
  static const conferirBateria = Duration(minutes: 10);

  final _amostrador = Amostrador();
  StreamSubscription<AmostraDePosicao>? _assinatura;
  Timer? _bateria;
  var _ligada = false;

  @override
  EstadoDaColeta build() {
    ref.listen(controleDoDiaProvider.select((d) => d.emJornada), (_, emJornada) {
      emJornada ? unawaited(_ligar()) : _desligar();
    });
    ref.onDispose(() => _desligar(publicar: false));
    Future.microtask(() {
      if (ref.mounted && ref.read(controleDoDiaProvider).emJornada) unawaited(_ligar());
    });
    return const EstadoDaColeta();
  }

  /// Ao voltar para o app: se a coleta parou por GPS desligado ou permissão, tenta de novo.
  Future<void> retomar() async {
    if (!ref.read(controleDoDiaProvider).emJornada || _assinatura != null) return;
    _ligada ? await _assinar(await _emEconomia()) : await _ligar();
  }

  Future<void> abrirAjustes() => ref.read(localizacaoProvider).abrirAjustes();

  Future<void> _ligar() async {
    if (_ligada) return;
    _ligada = true;
    // Sem a permissão de notificação, o Android 13+ esconde o aviso da jornada; o app pede uma vez por jornada.
    await ref.read(aparelhoProvider).pedirNotificacoes();
    if (!_ligada) return;
    await _assinar(await _emEconomia());
    _bateria ??= Timer.periodic(conferirBateria, (_) => unawaited(_conferirBateria()));
  }

  Future<void> _assinar(bool economia) async {
    await _assinatura?.cancel();
    if (!_ligada) return;
    _amostrador.recomecar();
    _publicar(EstadoDaColeta(ativa: true, ultima: state.ultima, posicao: state.posicao, economia: economia));
    _assinatura = ref
        .read(fonteDePosicoesProvider)
        .acompanhar(economia: economia)
        .listen(
          (leitura) => unawaited(_aoLer(leitura)),
          onError: (Object erro) {
            _assinatura?.cancel();
            _assinatura = null;
            final gps = erro is GpsIndisponivel ? erro : null;
            _publicar(
              EstadoDaColeta(
                ultima: state.ultima,
                posicao: state.posicao,
                economia: economia,
                problema: gps?.mensagem ?? 'O GPS parou de responder.',
                abrirAjustes: gps?.abrirAjustes ?? false,
              ),
            );
          },
          cancelOnError: true,
        );
  }

  Future<void> _aoLer(AmostraDePosicao leitura) async {
    if (!_ligada || !_amostrador.aceita(leitura, economia: state.economia)) return;
    await ref.read(filaProvider.notifier).sincronizador.registrarPosicao(leitura);
    _publicar(EstadoDaColeta(ativa: true, ultima: leitura.momento, posicao: leitura.posicao, economia: state.economia));
  }

  Future<void> _conferirBateria() async {
    final economia = await _emEconomia();
    if (_ligada && _assinatura != null && economia != state.economia) await _assinar(economia);
  }

  Future<bool> _emEconomia() async {
    final b = await ref.read(aparelhoProvider).bateria();
    return b != null && !b.carregando && b.nivel <= bateriaBaixa;
  }

  void _desligar({bool publicar = true}) {
    _ligada = false;
    _bateria?.cancel();
    _bateria = null;
    unawaited(_assinatura?.cancel());
    _assinatura = null;
    _amostrador.recomecar();
    if (publicar) _publicar(const EstadoDaColeta());
  }

  void _publicar(EstadoDaColeta novo) {
    if (ref.mounted) state = novo;
  }
}
