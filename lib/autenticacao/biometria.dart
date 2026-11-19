import 'package:local_auth/local_auth.dart';

/// Desbloqueio por digital ou rosto, quando o celular tem e o agente cadastrou.
abstract interface class Biometria {
  Future<bool> disponivel();
  Future<bool> autenticar(String motivo);
}

class BiometriaDoAparelho implements Biometria {
  final LocalAuthentication _local = LocalAuthentication();

  @override
  Future<bool> disponivel() async {
    try {
      return await _local.isDeviceSupported() && (await _local.getAvailableBiometrics()).isNotEmpty;
    } on Exception {
      return false;
    }
  }

  @override
  Future<bool> autenticar(String motivo) async {
    try {
      return await _local.authenticate(localizedReason: motivo, biometricOnly: true);
    } on Exception {
      return false;
    }
  }
}
