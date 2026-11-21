import 'package:aurora_campo/app/dependencias.dart';
import 'package:aurora_campo/app/tema_do_dia.dart';
import 'package:aurora_campo/autenticacao/cofre.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Modo noturno (decisão de 21/11/2026): escuro entre o pôr e o nascer do sol, ou a escolha do agente.
void main() {
  late CofreEmMemoria cofre;
  late DateTime agora;
  ProviderContainer? aberto;

  ProviderContainer criar() => aberto = ProviderContainer(
    overrides: [cofreProvider.overrideWithValue(cofre), relogioProvider.overrideWithValue(() => agora)],
  )..listen(temaDoDiaProvider, (_, _) {});

  setUp(() {
    cofre = CofreEmMemoria();
    agora = DateTime(2026, 11, 21, 12);
  });

  tearDown(() {
    aberto?.dispose();
    aberto = null;
  });

  test('automático: claro de dia e escuro à noite, mudando sozinho', () {
    fakeAsync((tempo) {
      agora = DateTime(2026, 11, 21, 17, 59);
      final c = criar();
      tempo.flushMicrotasks();
      expect(c.read(temaDoDiaProvider).preferencia, PreferenciaDeTema.automatico);
      expect(c.read(temaDoDiaProvider).modo, ThemeMode.light);

      agora = DateTime(2026, 11, 21, 18, 1);
      tempo.elapse(ControleDoTema.intervalo);
      expect(c.read(temaDoDiaProvider).modo, ThemeMode.dark);
    });
  });

  test('com o lugar do trabalho, vale o pôr do sol de lá (Limeira, verão: ainda claro às 18h30)', () async {
    agora = DateTime.utc(2026, 11, 21, 21, 30); // 18h30 em Brasília
    final c = criar();
    await c.read(temaDoDiaProvider.notifier).informarLocal(-22.56, -47.40);
    expect(c.read(temaDoDiaProvider).noite, isFalse);
    expect(await cofre.ler(ControleDoTema.chaveLocal), '-22.56,-47.4');
  });

  test('a escolha do agente vale sobre o horário e fica guardada', () async {
    final c = criar();
    await c.read(temaDoDiaProvider.notifier).escolher(PreferenciaDeTema.escuro);
    expect(c.read(temaDoDiaProvider).modo, ThemeMode.dark);
    expect(await cofre.ler(ControleDoTema.chavePreferencia), 'escuro');

    aberto!.dispose();
    final reaberto = criar();
    await Future<void>.delayed(Duration.zero);
    expect(reaberto.read(temaDoDiaProvider).preferencia, PreferenciaDeTema.escuro);
    expect(reaberto.read(temaDoDiaProvider).modo, ThemeMode.dark);
  });
}
