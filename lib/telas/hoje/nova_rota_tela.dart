import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/tema.dart';
import '../../dados/modelos/dia.dart';
import '../../jornada/controle_do_dia.dart';
import '../../nucleo/datas.dart';

void abrirNovaRota(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const NovaRotaTela()));

/// J7 (ADR 0050): a nova ordem das OS publicada no meio da jornada, comparada com a que o agente segue. Confirmar
/// troca a lista e o mapa e avisa o programador; até lá (ou sem sinal), vale a ordem anterior.
class NovaRotaTela extends ConsumerWidget {
  const NovaRotaTela({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dia = ref.watch(controleDoDiaProvider);
    final nova = dia.rotaNova;
    final c = context.cores;
    final texto = Theme.of(context).textTheme;
    final ordens = {for (final o in dia.pacote?.ordens ?? const <OrdemDoDia>[]) o.id: o};
    final antes = dia.rota?.ordem ?? const <String>[];

    return Scaffold(
      appBar: AppBar(title: const Text('Nova ordem das OS')),
      body: nova == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Nada para confirmar: você já está na ordem mais recente.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.textoSecundario),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                Text(
                  'A rota foi reorganizada${nova.publicadaEm == null ? '' : ' às ${hora(nova.publicadaEm!.toLocal())}'}. '
                  'Confira a nova sequência; até confirmar, você segue a ordem anterior.',
                  style: TextStyle(color: c.textoSecundario),
                ),
                const SizedBox(height: 8),
                Text(
                  'Fim previsto ${hora(nova.fimPrevisto.toLocal())} · '
                  '${nova.km.toStringAsFixed(1).replaceAll('.', ',')} km${nova.pelaMalha ? '' : ' (estimativa em linha reta)'}',
                  style: texto.labelLarge,
                ),
                const SizedBox(height: 12),
                for (final (i, id) in nova.ordem.indexed)
                  _Parada(posicao: i + 1, ordem: ordens[id], antes: antes.contains(id) ? antes.indexOf(id) + 1 : null),
                if (antes.where((id) => !nova.ordem.contains(id) && (ordens[id]?.aberta ?? false)).isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('Saíram da sua rota', style: texto.titleSmall),
                  for (final id in antes.where((id) => !nova.ordem.contains(id) && (ordens[id]?.aberta ?? false)))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(_nome(ordens[id]), style: TextStyle(color: c.textoSecundario)),
                    ),
                ],
              ],
            ),
      bottomNavigationBar: nova == null
          ? null
          : SafeArea(
              minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Agora não')),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: () async {
                        await ref.read(controleDoDiaProvider.notifier).confirmarRotaNova();
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Nova ordem confirmada. O programador foi avisado.')),
                        );
                        Navigator.of(context).pop();
                      },
                      icon: const Icon(Icons.check_rounded),
                      label: const Text('Confirmar nova ordem'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  static String _nome(OrdemDoDia? o) => o == null ? 'OS que não está no celular' : '${o.servicoNome} · ${o.endereco}';
}

class _Parada extends StatelessWidget {
  const _Parada({required this.posicao, required this.ordem, required this.antes});

  final int posicao;
  final OrdemDoDia? ordem;

  /// Posição na ordem anterior; nula quando a OS entrou agora na rota.
  final int? antes;

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    final (mudanca, cor, icone) = switch (antes) {
      null => ('Nova na sua rota', c.perigo, Icons.add_circle_rounded),
      final a when a > posicao => ('Subiu (era a $aª)', c.destaque, Icons.arrow_upward_rounded),
      final a when a < posicao => ('Desceu (era a $aª)', c.atencao, Icons.arrow_downward_rounded),
      _ => ('Mesma posição', c.neutro, Icons.drag_handle_rounded),
    };
    final o = ordem;
    return Semantics(
      label: 'Parada $posicao, ${o == null ? 'OS nova' : '${o.servicoNome}, ${o.endereco}'}, $mudanca',
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: o?.prioridade == Prioridade.emergencial ? c.perigo : c.destaque,
              foregroundColor: c.sobreDestaque,
              child: Text('$posicao', style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    o == null ? 'OS nova (baixando os dados)' : o.servicoNome,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (o != null) Text(o.endereco, style: TextStyle(color: c.textoSecundario)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(icone, color: cor, size: 20),
            const SizedBox(width: 4),
            Text(
              mudanca,
              style: TextStyle(color: cor, fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
