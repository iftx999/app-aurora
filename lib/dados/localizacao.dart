import 'package:geolocator_android/geolocator_android.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';

import 'api/api_campo.dart';

/// GPS desligado, permissão negada ou sem leitura a tempo; [mensagem] vai para a tela.
class GpsIndisponivel implements Exception {
  const GpsIndisponivel(this.mensagem, {this.abrirAjustes = false});

  final String mensagem;

  /// A permissão foi negada de vez: só nos ajustes do Android.
  final bool abrirAjustes;

  @override
  String toString() => 'GpsIndisponivel($mensagem)';
}

/// Leitura do GPS. A localização é usada só durante a jornada (RN-27, RIPD).
abstract interface class Localizacao {
  /// Posição atual com alta precisão; [GpsIndisponivel] quando não dá.
  Future<Posicao> atual();
  Future<void> abrirAjustes();
}

/// Pelo plugin do Android (geolocator_android, MIT), sem o pacote geral (que traz dependências MPL para Linux).
class LocalizacaoDoAparelho implements Localizacao {
  GeolocatorPlatform get _gps => GeolocatorPlatform.instance;

  @override
  Future<Posicao> atual() async {
    if (!await _gps.isLocationServiceEnabled()) {
      throw const GpsIndisponivel('Ligue a localização do celular para iniciar a jornada.');
    }
    var permissao = await _gps.checkPermission();
    if (permissao == LocationPermission.denied) {
      permissao = await _gps.requestPermission();
    }
    if (permissao == LocationPermission.deniedForever) {
      throw const GpsIndisponivel(
        'A localização foi negada para o Aurora Campo. Libere nos ajustes.',
        abrirAjustes: true,
      );
    }
    if (permissao == LocationPermission.denied || permissao == LocationPermission.unableToDetermine) {
      throw const GpsIndisponivel('Sem permissão de localização, a jornada não começa.');
    }
    try {
      final p = await _gps.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 20)),
      );
      return Posicao(p.latitude, p.longitude, precisaoM: p.accuracy);
    } on Exception {
      final ultima = await _gps.getLastKnownPosition();
      if (ultima == null) {
        throw const GpsIndisponivel('O GPS não respondeu. Vá para um lugar aberto e tente de novo.');
      }
      return Posicao(ultima.latitude, ultima.longitude, precisaoM: ultima.accuracy);
    }
  }

  @override
  Future<void> abrirAjustes() => _gps.openAppSettings();
}

/// Leituras contínuas do GPS durante a jornada (RN-27).
abstract interface class FonteDePosicoes {
  /// Leituras até cancelar a assinatura; erros do GPS (desligado, permissão retirada) chegam como
  /// [GpsIndisponivel]. [economia]: bateria baixa, leituras mais espaçadas e menos precisas.
  Stream<AmostraDePosicao> acompanhar({required bool economia});
}

/// Pelo serviço em primeiro plano do `geolocator_android`: notificação fixa enquanto coleta (o agente vê que está
/// sendo localizado) e o processo continua vivo com o app em segundo plano, inclusive para enviar a fila.
class PosicoesDoAparelho implements FonteDePosicoes {
  GeolocatorPlatform get _gps => GeolocatorPlatform.instance;

  @override
  Stream<AmostraDePosicao> acompanhar({required bool economia}) async* {
    if (!await _gps.isLocationServiceEnabled()) {
      throw const GpsIndisponivel('A localização do celular está desligada: ligue para registrar a jornada.');
    }
    final permissao = await _gps.checkPermission();
    if (permissao != LocationPermission.whileInUse && permissao != LocationPermission.always) {
      throw const GpsIndisponivel(
        'Sem permissão de localização, a jornada fica sem o trajeto. Libere nos ajustes.',
        abrirAjustes: true,
      );
    }
    final ajustes = AndroidSettings(
      accuracy: economia ? LocationAccuracy.medium : LocationAccuracy.high,
      // O filtro de 2 min ou 100 m é feito no app (Amostrador); aqui só o ritmo das leituras.
      intervalDuration: economia ? const Duration(minutes: 1) : const Duration(seconds: 30),
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: 'Jornada em andamento',
        notificationText: 'O Aurora Campo registra sua localização até você encerrar a jornada.',
        notificationChannelName: 'Jornada',
        notificationIcon: AndroidResource(name: 'ic_launcher', defType: 'mipmap'),
        setOngoing: true,
      ),
    );
    yield* _gps
        .getPositionStream(locationSettings: ajustes)
        .handleError((Object erro) {
          throw switch (erro) {
            LocationServiceDisabledException() => const GpsIndisponivel(
              'A localização do celular foi desligada: ligue para continuar registrando a jornada.',
            ),
            PermissionDeniedException() => const GpsIndisponivel(
              'A permissão de localização foi retirada. Libere nos ajustes.',
              abrirAjustes: true,
            ),
            _ => GpsIndisponivel('O GPS parou de responder ($erro).'),
          };
        })
        .map((p) => AmostraDePosicao(p.timestamp, Posicao(p.latitude, p.longitude, precisaoM: p.accuracy)));
  }
}
