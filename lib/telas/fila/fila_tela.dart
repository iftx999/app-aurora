import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/dependencias.dart';
import '../../app/tema.dart';
import '../../dados/modelos/dia.dart';
import '../../dados/modelos/evento.dart';
import '../../dados/modelos/foto.dart';
import '../../jornada/coleta_de_posicoes.dart';
import '../../jornada/controle_do_dia.dart';
import '../../nucleo/datas.dart';
import '../../sincronizacao/controle_da_fila.dart';
import '../../sincronizacao/sincronizador.dart';

void abrirFila(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const FilaTela()));

/// O que está no celular: ações e fotos (pendentes e respondidas nos últimos 2 dias), relido a cada mudança da fila.
final historicoDaFilaProvider = FutureProvider.autoDispose<({List<EventoNaFila> eventos, List<FotoDaOs> fotos})>((
  ref,
) async {
  ref.watch(filaProvider.select((f) => f.versao));
  final armazem = ref.watch(armazemProvider);
  return (eventos: (await armazem.eventos()).reversed.toList(), fotos: await armazem.fotos(soPendentes: true));
});

/// J10: a fila do celular em detalhe (o que falta enviar, o que o servidor respondeu e as posições da jornada).
class FilaTela extends ConsumerWidget {
  const FilaTela({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fila = ref.watch(filaProvider);
    final historico = ref.watch(historicoDaFilaProvider);
    final ordens = {for (final o in ref.watch(controleDoDiaProvider).pacote?.ordens ?? const <OrdemDoDia>[]) o.id: o};
    final c = context.cores;
    final texto = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Fila de envio')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _Resumo(fila: fila),
          const SizedBox(height: 12),
          SizedBox(
            height: 48,
            child: FilledButton.icon(
              onPressed: fila.enviando ? null : () => ref.read(filaProvider.notifier).sincronizador.enviar(),
              icon: const Icon(Icons.sync_rounded),
              label: Text(fila.enviando ? 'Enviando…' : 'Enviar agora'),
            ),
          ),
          const SizedBox(height: 20),
          const _Localizacao(),
          const SizedBox(height: 20),
          Text('Ações', style: texto.titleMedium),
          const SizedBox(height: 4),
          switch (historico) {
            AsyncData(:final value) when value.eventos.isEmpty && value.fotos.isEmpty => Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text('Nenhuma ação registrada nos últimos 2 dias.', style: TextStyle(color: c.textoSecundario)),
            ),
            AsyncData(:final value) => Column(
              children: [
                for (final f in value.fotos) _LinhaDaFoto(foto: f, ordem: ordens[f.osId]),
                for (final e in value.eventos) _LinhaDoEvento(evento: e, ordem: ordens[e.evento.osId]),
              ],
            ),
            AsyncError() => Text('Não foi possível ler a fila do celular.', style: TextStyle(color: c.perigo)),
            _ => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          },
        ],
      ),
    );
  }
}

class _Resumo extends StatelessWidget {
  const _Resumo({required this.fila});

  final EstadoDaFila fila;

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    final linhas = [
      ('Ações pendentes', '${fila.pendentes}'),
      ('Fotos pendentes', '${fila.fotosPendentes}'),
      ('Posições pendentes', '${fila.posicoesPendentes}'),
      ('Último envio', fila.ultimoEnvio == null ? 'nenhum nesta abertura' : hora(fila.ultimoEnvio!)),
      if (fila.proximaTentativa != null) ('Sem sinal; nova tentativa', hora(fila.proximaTentativa!)),
    ];
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (rotulo, valor) in linhas)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(rotulo, style: TextStyle(color: c.textoSecundario)),
                    ),
                    Text(valor, style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            if (fila.problema != null) ...[
              const SizedBox(height: 8),
              Text(fila.problema!, style: TextStyle(color: c.perigo)),
            ],
          ],
        ),
      ),
    );
  }
}

/// RN-27: se a localização está sendo registrada, desde quando e o que fazer quando parou.
class _Localizacao extends ConsumerWidget {
  const _Localizacao();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coleta = ref.watch(coletaProvider);
    final c = context.cores;
    final (icone, cor, titulo) = switch (coleta) {
      EstadoDaColeta(problema: final _?) => (Icons.location_disabled_rounded, c.perigo, 'Localização parada'),
      EstadoDaColeta(ativa: true) => (Icons.my_location_rounded, c.ok, 'Localização registrada'),
      _ => (Icons.location_off_rounded, c.neutro, 'Localização desligada'),
    };
    final detalhe =
        coleta.problema ??
        (coleta.ativa
            ? [
                'Uma posição a cada ${coleta.economia ? '5 min ou 250 m' : '2 min ou 100 m'}, só durante a jornada',
                if (coleta.economia) 'bateria baixa',
                if (coleta.ultima != null) 'última ${hora(coleta.ultima!)}',
              ].join(' · ')
            : 'Só é registrada com a jornada aberta.');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icone, color: cor),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(titulo, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(detalhe, style: TextStyle(color: c.textoSecundario)),
              if (coleta.abrirAjustes)
                TextButton(
                  onPressed: ref.read(coletaProvider.notifier).abrirAjustes,
                  child: const Text('Abrir ajustes'),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

String _nomeDaOrdem(OrdemDoDia? o) => o == null ? 'OS fora da lista de hoje' : '${o.servicoNome} · ${o.endereco}';

class _LinhaDoEvento extends StatelessWidget {
  const _LinhaDoEvento({required this.evento, required this.ordem});

  final EventoNaFila evento;
  final OrdemDoDia? ordem;

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    final (selo, cor) = switch (evento.situacao) {
      SituacaoDoEnvio.pendente => (
        evento.tentativas > 0 ? 'Pendente · ${evento.tentativas}ª tentativa' : 'Pendente',
        c.atencao,
      ),
      SituacaoDoEnvio.aplicado || SituacaoDoEnvio.repetido => ('Recebida', c.ok),
      SituacaoDoEnvio.aguardando => ('Recebida · aguarda a anterior', c.ok),
      SituacaoDoEnvio.conflito => ('Conflito', c.atencao),
      SituacaoDoEnvio.superado => ('Superada', c.neutro),
      SituacaoDoEnvio.rejeitado => ('Recusada', c.perigo),
    };
    return _Linha(
      titulo: '${evento.evento.acao.rotulo} · ${hora(evento.evento.ocorridoEm)}',
      subtitulo: [_nomeDaOrdem(ordem), ?evento.mensagem].join('\n'),
      selo: selo,
      cor: cor,
    );
  }
}

class _LinhaDaFoto extends StatelessWidget {
  const _LinhaDaFoto({required this.foto, required this.ordem});

  final FotoDaOs foto;
  final OrdemDoDia? ordem;

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    final enviado = foto.tamanho == 0 ? 0 : (foto.recebido * 100 ~/ foto.tamanho);
    return _Linha(
      titulo: 'Foto · ${hora(foto.tiradaEm)}',
      subtitulo: _nomeDaOrdem(ordem),
      selo: enviado > 0 ? 'Enviando · $enviado%' : 'Pendente',
      cor: c.atencao,
    );
  }
}

class _Linha extends StatelessWidget {
  const _Linha({required this.titulo, required this.subtitulo, required this.selo, required this.cor});

  final String titulo;
  final String subtitulo;
  final String selo;
  final Color cor;

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    return Semantics(
      label: '$titulo, $subtitulo, $selo',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titulo, style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(subtitulo, style: TextStyle(color: c.textoSecundario)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: cor.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(99)),
              child: Text(
                selo,
                style: TextStyle(color: cor, fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
