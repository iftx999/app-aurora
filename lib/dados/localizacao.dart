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
