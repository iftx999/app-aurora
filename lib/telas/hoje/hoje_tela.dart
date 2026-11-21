import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/dependencias.dart';
import '../../app/tema.dart';
import '../../dados/modelos/dia.dart';
import '../../dados/modelos/evento.dart';
import '../../jornada/coleta_de_posicoes.dart';
import '../../jornada/controle_do_dia.dart';
import '../../nucleo/datas.dart';
import '../../sincronizacao/controle_da_fila.dart';
import '../comum/menu_da_conta.dart';
import '../comum/navegar.dart';
import '../fila/fila_tela.dart';
import '../mapa/mapa_tela.dart';
import '../ordem/ordem_tela.dart';
import 'nova_rota_tela.dart';

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
    // Ação recusada, superada ou em conflito: o agente precisa saber (10.9.5).
    ref.listen(filaProvider.select((f) => f.avisosDeFoto), (_, avisos) {
      if (avisos.isEmpty) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(avisos.join(' ')), duration: const Duration(seconds: 8)));
      ref.read(filaProvider.notifier).sincronizador.dispensarAvisos();
    });
    ref.listen(filaProvider.select((f) => f.avisos), (_, avisos) {
      if (avisos.isEmpty) return;
      final primeiro = avisos.first;
      final texto =
          '${primeiro.evento.acao.rotulo} da OS: ${primeiro.mensagem ?? _motivo(primeiro.situacao)}'
          '${avisos.length > 1 ? ' (e mais ${avisos.length - 1})' : ''}';
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(texto), duration: const Duration(seconds: 8)));
      ref.read(filaProvider.notifier).sincronizador.dispensarAvisos();
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
          IconButton(onPressed: () => abrirMapa(context), tooltip: 'Mapa da rota', icon: const Icon(Icons.map_rounded)),
          MenuDaConta(
            acoes: {'Fila de envio': () => abrirFila(context), 'Encerrar jornada': () => _encerrar(context, ref)},
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: controle.atualizar,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            _Situacao(dia: dia),
            const SizedBox(height: 8),
            const _Fila(),
            const _Coleta(),
            if (dia.rotaNova != null) ...[const SizedBox(height: 8), const _NovaOrdem()],
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

  static String _motivo(SituacaoDoEnvio s) => switch (s) {
    SituacaoDoEnvio.superado => 'a programação mudou e a OS saiu da sua lista.',
    SituacaoDoEnvio.conflito => 'registrada; a programação mudou e o programador vai decidir.',
    _ => 'recusada pelo servidor.',
  };

  static int _posicaoNaLista(PacoteDoDia p, OrdemDoDia o) => o.sequencia ?? (p.ordens.indexOf(o) + 1);

  Future<void> _encerrar(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (contexto) => AlertDialog(
        title: const Text('Encerrar a jornada?'),
        content: Text(
          'O envio da sua localização para. Você só volta a receber OS ao iniciar outra jornada.'
          '${switch (ref.read(filaProvider).pendentes) {
            0 => '',
            1 => '\n\nAntes, a ação que está na fila vai ser enviada.',
            final n => '\n\nAntes, as $n ações que estão na fila vão ser enviadas.',
          }}',
        ),
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

/// J10: "2 ações pendentes · último envio 14:32", sempre à vista, com "Enviar agora".
class _Fila extends ConsumerWidget {
  const _Fila();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fila = ref.watch(filaProvider);
    final c = context.cores;
    final envio = fila.ultimoEnvio == null ? null : 'último envio ${hora(fila.ultimoEnvio!)}';
    final texto = [_pendencias(fila.pendentes, fila.fotosPendentes), ?envio, ?fila.problema].join(' · ');
    return Semantics(
      liveRegion: true,
      child: InkWell(
        onTap: () => abrirFila(context),
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(
            children: [
              Icon(
                fila.vazia ? Icons.done_all_rounded : Icons.schedule_send_rounded,
                size: 20,
                color: fila.vazia ? c.ok : c.atencao,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(texto, style: TextStyle(color: c.textoSecundario)),
              ),
              if (!fila.vazia)
                TextButton(
                  onPressed: fila.enviando ? null : () => ref.read(filaProvider.notifier).sincronizador.enviar(),
                  child: Text(fila.enviando ? 'Enviando…' : 'Enviar agora'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// RN-27: o agente vê que a localização está sendo registrada (e quando parou, por quê).
class _Coleta extends ConsumerWidget {
  const _Coleta();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coleta = ref.watch(coletaProvider);
    final c = context.cores;
    if (!coleta.ativa && coleta.problema == null) return const SizedBox.shrink();
    final parada = coleta.problema != null;
    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          children: [
            Icon(
              parada ? Icons.location_disabled_rounded : Icons.my_location_rounded,
              size: 20,
              color: parada ? c.perigo : c.ok,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                coleta.problema ??
                    [
                      'Localização registrada',
                      if (coleta.economia) 'economia de bateria',
                      if (coleta.ultima != null) 'última ${hora(coleta.ultima!)}',
                    ].join(' · '),
                style: TextStyle(color: parada ? c.perigo : c.textoSecundario),
              ),
            ),
            if (coleta.abrirAjustes)
              TextButton(onPressed: ref.read(coletaProvider.notifier).abrirAjustes, child: const Text('Ajustes')),
          ],
        ),
      ),
    );
  }
}

/// "Tudo enviado", "1 ação pendente", "2 ações e 3 fotos pendentes".
String _pendencias(int acoes, int fotos) {
  if (acoes == 0 && fotos == 0) return 'Tudo enviado';
  final partes = [
    if (acoes > 0) acoes == 1 ? '1 ação' : '$acoes ações',
    if (fotos > 0) fotos == 1 ? '1 foto' : '$fotos fotos',
  ];
  return '${partes.join(' e ')} ${acoes + fotos == 1 ? 'pendente' : 'pendentes'}';
}

/// J7 (ADR 0050): a nova ordem publicada espera o agente conferir; até lá, a lista segue a ordem anterior.
class _NovaOrdem extends StatelessWidget {
  const _NovaOrdem();

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    return Card(
      margin: EdgeInsets.zero,
      color: c.superficie,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: c.atencao, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.alt_route_rounded, color: c.atencao),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Nova ordem das OS',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'A rota foi reorganizada. Confira antes de seguir para a próxima parada.',
              style: TextStyle(color: c.textoSecundario),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(onPressed: () => abrirNovaRota(context), child: const Text('Conferir e confirmar')),
            ),
          ],
        ),
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
                  child: OutlinedButton(onPressed: () => abrirOrdem(context, ordem), child: const Text('Ver OS')),
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
        onTap: () => abrirOrdem(context, ordem),
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
