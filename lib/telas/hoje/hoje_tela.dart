import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/dependencias.dart';
import '../../app/tema.dart';
import '../../dados/modelos/dia.dart';
import '../../jornada/controle_do_dia.dart';
import '../../nucleo/datas.dart';
import '../comum/menu_da_conta.dart';

/// "Hoje" (J8; protótipo `Main`): a OS atual com o botão Navegar e a lista do dia na ordem da rota.
class HojeTela extends ConsumerWidget {
  const HojeTela({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dia = ref.watch(controleDoDiaProvider);
    final controle = ref.read(controleDoDiaProvider.notifier);
    final pacote = dia.pacote;
    final agora = ref.read(relogioProvider)();
    final c = context.cores;

    ref.listen(controleDoDiaProvider.select((d) => d.erro), (_, erro) {
      if (erro == null) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(erro)));
      controle.dispensarErro();
    });

    final atual = pacote?.atual;
    final outras = pacote?.ordens.where((o) => o.id != atual?.id).toList() ?? const <OrdemDoDia>[];

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Hoje · ${diaCurto(agora)}'),
            if (pacote != null)
              Text(
                '${pacote.equipeNome} · ${pacote.ordens.length} OS',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: c.textoSecundario),
              ),
          ],
        ),
        actions: [
          MenuDaConta(acoes: {'Encerrar jornada': () => _encerrar(context, ref)}),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: controle.atualizar,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            _Situacao(dia: dia),
            const SizedBox(height: 12),
            if (pacote == null || pacote.ordens.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Nenhuma OS programada para a equipe hoje. Puxe para atualizar.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.textoSecundario),
                ),
              )
            else ...[
              if (atual != null) _CartaoAtual(ordem: atual, posicao: _posicaoNaLista(pacote, atual)),
              const SizedBox(height: 12),
              for (final o in outras) _LinhaDaOrdem(ordem: o, posicao: _posicaoNaLista(pacote, o), agora: agora),
            ],
          ],
        ),
      ),
    );
  }

  static int _posicaoNaLista(PacoteDoDia p, OrdemDoDia o) => o.sequencia ?? (p.ordens.indexOf(o) + 1);

  Future<void> _encerrar(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (contexto) => AlertDialog(
        title: const Text('Encerrar a jornada?'),
        content: const Text('O envio da sua localização para. Você só volta a receber OS ao iniciar outra jornada.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(contexto, false), child: const Text('Continuar trabalhando')),
          FilledButton(onPressed: () => Navigator.pop(contexto, true), child: const Text('Encerrar')),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(controleDoDiaProvider.notifier).encerrar();
    }
  }
}

/// "Jornada desde 07:12 · atualizado 14:32", ou o aviso de sem sinal.
class _Situacao extends StatelessWidget {
  const _Situacao({required this.dia});

  final EstadoDoDia dia;

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    final inicio = dia.pacote?.jornada?.inicio ?? dia.inicioPendente?.ocorridoEm;
    final partes = [
      if (inicio != null) 'Jornada desde ${hora(inicio)}',
      if (dia.inicioPendente != null) 'início ainda não enviado',
      if (dia.baixadoEm != null) 'atualizado ${hora(dia.baixadoEm!)}',
    ];
    final cor = dia.semSinal ? c.atencao : c.ok;
    return Semantics(
      liveRegion: true,
      child: Row(
        children: [
          Icon(dia.semSinal ? Icons.cloud_off_rounded : Icons.cloud_done_rounded, size: 20, color: cor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              [if (dia.semSinal) 'Sem sinal', ...partes].join(' · '),
              style: TextStyle(color: c.textoSecundario),
            ),
          ),
          if (dia.ocupado) const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        ],
      ),
    );
  }
}

class _CartaoAtual extends StatelessWidget {
  const _CartaoAtual({required this.ordem, required this.posicao});

  final OrdemDoDia ordem;
  final int posicao;

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    final texto = Theme.of(context).textTheme;
    final emExecucao = ordem.status == StatusOrdem.emExecucao;
    return Card(
      margin: EdgeInsets.zero,
      color: c.superficie,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: c.destaque, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${emExecucao ? 'Em execução' : 'Próxima'} · parada $posicao',
              style: texto.labelLarge?.copyWith(color: c.destaque, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(ordem.servicoNome, style: texto.titleLarge),
            const SizedBox(height: 2),
            Text(ordem.endereco, style: TextStyle(color: c.textoSecundario)),
            if (ordem.prioridade == Prioridade.emergencial) ...[
              const SizedBox(height: 8),
              _Selo(texto: 'Emergencial', cor: c.perigo),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(onPressed: () => mostrarOrdem(context, ordem), child: const Text('Ver OS')),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => navegar(context, ordem),
                    icon: const Icon(Icons.navigation_rounded),
                    label: const Text('Navegar'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LinhaDaOrdem extends StatelessWidget {
  const _LinhaDaOrdem({required this.ordem, required this.posicao, required this.agora});

  final OrdemDoDia ordem;
  final int posicao;
  final DateTime agora;

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    final (selo, cor) = switch (ordem) {
      OrdemDoDia(status: StatusOrdem.encerrada) => ('Encerrada', c.ok),
      OrdemDoDia(status: StatusOrdem.devolvida) => ('Devolvida', c.neutro),
      OrdemDoDia(status: StatusOrdem.cancelada) => ('Cancelada', c.neutro),
      OrdemDoDia(status: StatusOrdem.paralisada) => ('Paralisada', c.atencao),
      OrdemDoDia(prioridade: Prioridade.emergencial) => ('Emergencial', c.perigo),
      _ => (prazo(ordem.prazo, agora), ordem.atrasada ? c.perigo : c.neutro),
    };
    final fechada = !ordem.aberta;
    return Semantics(
      button: true,
      label: 'Parada $posicao, ${ordem.servicoNome}, ${ordem.endereco}, $selo',
      excludeSemantics: true,
      child: InkWell(
        onTap: () => mostrarOrdem(context, ordem),
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: fechada
                      ? c.neutro
                      : (ordem.prioridade == Prioridade.emergencial ? c.perigo : c.destaque),
                  foregroundColor: fechada ? c.fundo : c.sobreDestaque,
                  child: Text('$posicao', style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ordem.servicoNome,
                        style: TextStyle(fontWeight: FontWeight.w600, color: fechada ? c.textoSecundario : c.texto),
                      ),
                      Text(ordem.endereco, style: TextStyle(color: c.textoSecundario)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _Selo(texto: selo, cor: cor),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Selo extends StatelessWidget {
  const _Selo({required this.texto, required this.cor});

  final String texto;
  final Color cor;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: cor.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(99)),
    child: Text(
      texto,
      style: TextStyle(color: cor, fontWeight: FontWeight.w700, fontSize: 13),
    ),
  );
}

/// Abre o app de navegação escolhido no celular (Waze, Google Maps) no destino da OS.
Future<void> navegar(BuildContext context, OrdemDoDia ordem) async {
  final lat = ordem.latitude, lon = ordem.longitude;
  final destino = lat != null && lon != null
      ? Uri.parse('geo:$lat,$lon?q=$lat,$lon')
      : Uri(scheme: 'geo', path: '0,0', queryParameters: {'q': ordem.endereco});
  final mensageiro = ScaffoldMessenger.of(context);
  if (!await launchUrl(destino, mode: LaunchMode.externalApplication)) {
    mensageiro.showSnackBar(const SnackBar(content: Text('Nenhum app de mapa instalado.')));
  }
}

/// Resumo da OS. A execução (iniciar, paralisar, encerrar) entra no M6d.
void mostrarOrdem(BuildContext context, OrdemDoDia ordem) {
  final c = context.cores;
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('OS ${ordem.numero}', style: TextStyle(color: c.textoSecundario)),
            Text(ordem.servicoNome, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(ordem.endereco),
            if (ordem.matricula != null)
              Text('Matrícula ${ordem.matricula}', style: TextStyle(color: c.textoSecundario)),
            const SizedBox(height: 8),
            Text('Prazo: ${diaCurto(ordem.prazo.toLocal())} às ${hora(ordem.prazo)}'),
            Text('Previsto: ${ordem.quantidadePrevista} ${ordem.unidadeMedida}'),
            if (ordem.instrucoes case final i? when i.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Instruções', style: Theme.of(context).textTheme.titleSmall),
              Text(i),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => navegar(context, ordem),
              icon: const Icon(Icons.navigation_rounded),
              label: const Text('Navegar'),
            ),
          ],
        ),
      ),
    ),
  );
}
