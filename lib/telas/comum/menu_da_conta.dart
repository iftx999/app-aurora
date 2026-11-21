import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/dependencias.dart';
import '../../app/tema_do_dia.dart';

/// Menu das telas do dia: ações da tela (como encerrar a jornada), tema, bloquear e sair.
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
        PopupMenuItem(value: () => escolherTema(context, ref), child: const Text('Tema da tela')),
        PopupMenuItem(value: () => sessao.bloquear(), child: const Text('Bloquear')),
        PopupMenuItem(value: () => sessao.sair(), child: const Text('Sair da conta')),
      ],
    );
  }
}

/// Modo noturno automático, sempre claro ou sempre escuro.
Future<void> escolherTema(BuildContext context, WidgetRef ref) async {
  final atual = ref.read(temaDoDiaProvider).preferencia;
  final escolhida = await showDialog<PreferenciaDeTema>(
    context: context,
    builder: (contexto) => SimpleDialog(
      title: const Text('Tema da tela'),
      children: [
        RadioGroup<PreferenciaDeTema>(
          groupValue: atual,
          onChanged: (p) => Navigator.of(contexto).pop(p),
          child: Column(
            children: [
              for (final p in PreferenciaDeTema.values)
                RadioListTile<PreferenciaDeTema>(
                  value: p,
                  title: Text(p.rotulo),
                  subtitle: p == PreferenciaDeTema.automatico
                      ? const Text('Pelo nascer e pôr do sol onde a equipe trabalha')
                      : null,
                ),
            ],
          ),
        ),
      ],
    ),
  );
  if (escolhida != null) await ref.read(temaDoDiaProvider.notifier).escolher(escolhida);
}
