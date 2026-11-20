import 'package:flutter/services.dart';

/// O que o app pergunta ao Android sem plugin (canal em `MainActivity.kt`).
abstract interface class Aparelho {
  /// Nível da bateria (0 a 100) e se está carregando; nulo se o Android não informar.
  Future<({int nivel, bool carregando})?> bateria();

  /// Pede a permissão de notificação (Android 13+), sem esperar a resposta; verdadeiro se já havia.
  Future<bool> pedirNotificacoes();
}

class AparelhoAndroid implements Aparelho {
  static const _canal = MethodChannel('dev.aurora.campo/aparelho');

  @override
  Future<({int nivel, bool carregando})?> bateria() async {
    try {
      final r = await _canal.invokeMapMethod<String, Object?>('bateria');
      final nivel = r?['nivel'];
      if (nivel is! int || nivel < 0) return null;
      return (nivel: nivel, carregando: r?['carregando'] == true);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<bool> pedirNotificacoes() async {
    try {
      return await _canal.invokeMethod<bool>('pedirNotificacoes') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
