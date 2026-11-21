import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../nucleo/sol.dart';
import 'dependencias.dart';

/// Escolha do agente no menu: modo noturno automático (padrão), sempre claro ou sempre escuro.
enum PreferenciaDeTema {
  automatico('Automático (escuro à noite)'),
  claro('Sempre claro'),
  escuro('Sempre escuro');

  const PreferenciaDeTema(this.rotulo);
  final String rotulo;
}

class EstadoDoTema {
  const EstadoDoTema({
    this.preferencia = PreferenciaDeTema.automatico,
    this.latitude,
    this.longitude,
    this.noite = false,
  });

  final PreferenciaDeTema preferencia;

  /// Último lugar conhecido do trabalho (rota ou início da jornada), para o nascer e o pôr do sol.
  final double? latitude;
  final double? longitude;
  final bool noite;

  ThemeMode get modo => switch (preferencia) {
    PreferenciaDeTema.claro => ThemeMode.light,
    PreferenciaDeTema.escuro => ThemeMode.dark,
    PreferenciaDeTema.automatico => noite ? ThemeMode.dark : ThemeMode.light,
  };
}

final temaDoDiaProvider = NotifierProvider<ControleDoTema, EstadoDoTema>(ControleDoTema.new);

/// Modo noturno (decisão do cliente, 21/11/2026): no automático, escuro entre o pôr e o nascer do sol no lugar do
/// trabalho; sem lugar conhecido, das 18h às 6h. Reavalia a cada minuto. A escolha fica guardada no cofre.
class ControleDoTema extends Notifier<EstadoDoTema> {
  static const chavePreferencia = 'tema.preferencia';
  static const chaveLocal = 'tema.local';
  static const intervalo = Duration(minutes: 1);

  @override
  EstadoDoTema build() {
    final relogio = Timer.periodic(intervalo, (_) => _reavaliar());
    ref.onDispose(relogio.cancel);
    unawaited(_carregar());
    return EstadoDoTema(noite: eNoite(ref.read(relogioProvider)()));
  }

  Future<void> _carregar() async {
    final cofre = ref.read(cofreProvider);
    final guardada = await cofre.ler(chavePreferencia);
    final local = (await cofre.ler(chaveLocal))?.split(',');
    if (!ref.mounted) return;
    final preferencia = PreferenciaDeTema.values.where((p) => p.name == guardada).firstOrNull;
    final lat = local == null || local.length != 2 ? null : double.tryParse(local[0]);
    final lon = local == null || local.length != 2 ? null : double.tryParse(local[1]);
    state = _calcular(preferencia ?? state.preferencia, lat ?? state.latitude, lon ?? state.longitude);
  }

  Future<void> escolher(PreferenciaDeTema preferencia) async {
    state = _calcular(preferencia, state.latitude, state.longitude);
    await ref.read(cofreProvider).escrever(chavePreferencia, preferencia.name);
  }

  /// O dia informa onde a equipe trabalha (partida da rota ou posição do início da jornada).
  Future<void> informarLocal(double latitude, double longitude) async {
    if (state.latitude == latitude && state.longitude == longitude) return;
    state = _calcular(state.preferencia, latitude, longitude);
    await ref.read(cofreProvider).escrever(chaveLocal, '$latitude,$longitude');
  }

  void _reavaliar() {
    final novo = _calcular(state.preferencia, state.latitude, state.longitude);
    if (novo.noite != state.noite) state = novo;
  }

  EstadoDoTema _calcular(PreferenciaDeTema preferencia, double? lat, double? lon) => EstadoDoTema(
    preferencia: preferencia,
    latitude: lat,
    longitude: lon,
    noite: eNoite(ref.read(relogioProvider)(), latitude: lat, longitude: lon),
  );
}
