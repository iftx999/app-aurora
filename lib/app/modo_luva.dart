import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dependencias.dart';

final modoLuvaProvider = NotifierProvider<ControleDoModoLuva, bool>(ControleDoModoLuva.new);

/// Modo luva (ADR 0051): botões maiores no app inteiro e as ações da OS por toque longo, para não acionar sem
/// querer com a luva. Escolha do agente no menu, guardada no cofre.
class ControleDoModoLuva extends Notifier<bool> {
  static const chave = 'modo_luva';

  @override
  bool build() {
    unawaited(_carregar());
    return false;
  }

  Future<void> _carregar() async {
    final guardado = await ref.read(cofreProvider).ler(chave);
    if (ref.mounted && guardado == 'sim') state = true;
  }

  Future<void> definir(bool ligado) async {
    state = ligado;
    await ref.read(cofreProvider).escrever(chave, ligado ? 'sim' : 'nao');
  }
}
