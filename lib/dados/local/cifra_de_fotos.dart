import 'package:flutter/services.dart';

/// Criptografia das fotos guardadas no celular (ADR 0051): AES-256-GCM com a chave no Android Keystore (não sai do
/// aparelho). O arquivo cifrado traz o vetor de 12 bytes no começo e a etiqueta de autenticação no fim.
abstract interface class CifraDeFotos {
  Future<Uint8List> cifrar(Uint8List claro);

  /// Falha se o arquivo foi alterado (a etiqueta do GCM não confere) ou a chave foi apagada.
  Future<Uint8List> decifrar(Uint8List cifrado);

  /// Revogação ou troca de empresa: sem a chave, o que sobrar no armazenamento fica ilegível.
  Future<void> apagarChave();
}

class CifraDoAndroid implements CifraDeFotos {
  static const _canal = MethodChannel('dev.aurora.campo/aparelho');

  @override
  Future<Uint8List> cifrar(Uint8List claro) async => (await _canal.invokeMethod<Uint8List>('cifrar', claro))!;

  @override
  Future<Uint8List> decifrar(Uint8List cifrado) async => (await _canal.invokeMethod<Uint8List>('decifrar', cifrado))!;

  @override
  Future<void> apagarChave() async {
    try {
      await _canal.invokeMethod<void>('apagarChaveDasFotos');
    } on MissingPluginException {
      // Fora do Android.
    }
  }
}
