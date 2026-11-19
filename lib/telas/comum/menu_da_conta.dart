import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/dependencias.dart';

/// Menu das telas do dia: ações da tela (como encerrar a jornada), bloquear e sair.
class MenuDaConta extends ConsumerWidget {
  const MenuDaConta({super.key, this.acoes = const {}});

  /// Rótulo → ação, antes de "Bloquear" e "Sair".
  final Map<String, VoidCallback> acoes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessao = ref.read(sessaoProvider.notifier).sessao;
    return PopupMenuButton<VoidCallback>(
      tooltip: 'Mais opções',
      onSelected: (acao) => acao(),
      itemBuilder: (_) => [
        for (final MapEntry(:key, :value) in acoes.entries) PopupMenuItem(value: value, child: Text(key)),
        PopupMenuItem(value: () => sessao.bloquear(), child: const Text('Bloquear')),
        PopupMenuItem(value: () => sessao.sair(), child: const Text('Sair da conta')),
      ],
    );
  }
}
