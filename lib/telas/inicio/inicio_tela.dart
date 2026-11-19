import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/dependencias.dart';
import '../../autenticacao/estado_sessao.dart';

/// Ponto de chegada depois de desbloquear. A jornada e a lista do dia entram na etapa seguinte (M6b).
class InicioTela extends ConsumerWidget {
  const InicioTela({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final estado = ref.watch(sessaoProvider);
    final nome = estado is Desbloqueada ? estado.nome : '';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Aurora Campo'),
        actions: [
          IconButton(
            tooltip: 'Bloquear',
            icon: const Icon(Icons.lock_outline),
            onPressed: () => ref.read(sessaoProvider.notifier).sessao.bloquear(),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Bom dia${nome.isEmpty ? '' : ', $nome'}', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            const Text('Celular cadastrado. A jornada e as OS do dia chegam na próxima versão.'),
            const Spacer(),
            OutlinedButton(
              onPressed: () => ref.read(sessaoProvider.notifier).sessao.sair(),
              child: const Text('Sair'),
            ),
          ],
        ),
      ),
    );
  }
}

class TelaCarregando extends StatelessWidget {
  const TelaCarregando({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: CircularProgressIndicator()));
}
