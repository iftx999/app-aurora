import 'package:flutter/services.dart';

/// O que o app pergunta ao Android sem plugin (canal em `MainActivity.kt`).
/// Canais de notificação do app (cada um com seu som e vibração, ajustáveis pelo agente no Android).
enum CanalDeAviso { rota, emergencial }

abstract interface class Aparelho {
  /// Nível da bateria (0 a 100) e se está carregando; nulo se o Android não informar.
  Future<({int nivel, bool carregando})?> bateria();

  /// Pede a permissão de notificação (Android 13+), sem esperar a resposta; verdadeiro se já havia.
  Future<bool> pedirNotificacoes();

  /// Notificação do Android que abre o app ao tocar; [id] repetido substitui. [canal]: a nova ordem das OS (padrão)
  /// ou a OS emergencial, que toca e vibra mais forte (ADR 0051).
  Future<void> avisar({required int id, required String titulo, required String texto, CanalDeAviso canal});
}

class AparelhoAndroid implements Aparelho {
  static const _canal = MethodChannel('dev.aurora.campo/aparelho');

  /// Configuração gerenciada do Android Enterprise (chaves de `res/xml/app_restrictions.xml`); vazia sem MDM.
  static Future<Map<String, Object?>> configuracaoGerenciada() async {
    try {
      return await _canal.invokeMapMethod<String, Object?>('configuracaoGerenciada') ?? const {};
    } on PlatformException {
      return const {};
    } on MissingPluginException {
      return const {};
    }
  }

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
  Future<void> avisar({
    required int id,
    required String titulo,
    required String texto,
    CanalDeAviso canal = CanalDeAviso.rota,
  }) async {
    try {
      await _canal.invokeMethod<void>('avisar', {'id': id, 'titulo': titulo, 'texto': texto, 'canal': canal.name});
    } on PlatformException {
      // Sem permissão de notificação: o aviso continua na tela Hoje.
    } on MissingPluginException {
      // Fora do Android (testes).
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
