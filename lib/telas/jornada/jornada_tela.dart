import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/dependencias.dart';
import '../../app/tema.dart';
import '../../autenticacao/estado_sessao.dart';
import '../../dados/modelos/dia.dart';
import '../../jornada/controle_do_dia.dart';
import '../../nucleo/datas.dart';
import '../comum/menu_da_conta.dart';

/// "Iniciar jornada" (J8; protótipo `Jornada`): escolhe a equipe, mostra o que o celular já tem e abre a jornada.
class JornadaTela extends ConsumerStatefulWidget {
  const JornadaTela({super.key});

  @override
  ConsumerState<JornadaTela> createState() => _JornadaTelaState();
}

class _JornadaTelaState extends ConsumerState<JornadaTela> {
  String? _escolhida;

  @override
  Widget build(BuildContext context) {
    final dia = ref.watch(controleDoDiaProvider);
    final controle = ref.read(controleDoDiaProvider.notifier);
    final sessao = ref.watch(sessaoProvider);
    final nome = sessao is Desbloqueada ? sessao.nome : '';
    final agora = ref.read(relogioProvider)();
    final c = context.cores;
    final texto = Theme.of(context).textTheme;

    final equipes =
        dia.equipes ??
        [
          // Sem sinal: só a equipe da programação guardada.
          if (dia.pacote case final p?)
            EquipeDoDia(id: p.equipeId, nome: p.equipeNome, ordensHoje: p.abertas, emergenciais: 0),
        ];
    final escolhida =
        _escolhida ??
        (equipes.where((e) => e.jornadaAberta).firstOrNull ?? (equipes.length == 1 ? equipes.first : null))?.id;

    return Scaffold(
      appBar: AppBar(title: const Text('Iniciar jornada'), actions: const [MenuDaConta()]),
      body: RefreshIndicator(
        onRefresh: controle.atualizar,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Text(diaPorExtenso(agora), style: texto.bodyMedium?.copyWith(color: c.textoSecundario)),
            const SizedBox(height: 4),
            Text('${saudacao(agora)}${nome.isEmpty ? '' : ', $nome'}', style: texto.headlineSmall),
            const SizedBox(height: 24),
            Text('Com qual equipe você sai hoje?', style: texto.titleMedium),
            const SizedBox(height: 12),
            if (!dia.carregado || (dia.equipes == null && dia.ocupado))
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (equipes.isEmpty)
              Text(
                dia.semSinal
                    ? 'Sem sinal e sem programação guardada. Procure um lugar com sinal e puxe para atualizar.'
                    : 'Você não está em nenhuma equipe ativa. Fale com o gestor de serviços.',
                style: texto.bodyMedium?.copyWith(color: c.textoSecundario),
              )
            else
              RadioGroup<String>(
                groupValue: escolhida,
                onChanged: (v) => setState(() => _escolhida = v),
                child: Column(
                  children: [
                    for (final e in equipes)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _CartaoDaEquipe(
                          equipe: e,
                          marcada: e.id == escolhida,
                          aoEscolher: () => setState(() => _escolhida = e.id),
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            _Checagem(ok: !dia.semSinal, texto: dia.semSinal ? 'Sem sinal agora' : 'Conectado'),
            _Checagem(
              ok: dia.pacote != null && dia.baixadoEm != null,
              texto: dia.baixadoEm == null
                  ? 'Nenhuma programação guardada no celular'
                  : 'Programação de ${dia.pacote!.equipeNome} baixada às ${hora(dia.baixadoEm!)}',
            ),
            const SizedBox(height: 16),
            Text(
              'Sua localização é usada só durante a jornada para calcular a rota e acompanhar as OS. '
              'Ao encerrar a jornada, o envio para.',
              style: texto.bodySmall?.copyWith(color: c.textoTerciario),
            ),
            if (dia.erro case final erro?) ...[
              const SizedBox(height: 16),
              _Aviso(
                texto: erro,
                acao: dia.abrirAjustes ? 'Abrir ajustes' : null,
                aoAgir: () => ref.read(localizacaoProvider).abrirAjustes(),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: escolhida == null || dia.ocupado ? null : () => controle.iniciar(escolhida),
              icon: dia.ocupado
                  ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
                  : const Icon(Icons.play_arrow_rounded),
              label: const Text('Iniciar jornada'),
            ),
            const SizedBox(height: 8),
            Text(
              'Com sinal: a rota é calculada a partir de onde você está. Sem sinal: segue a programação já baixada.',
              textAlign: TextAlign.center,
              style: texto.bodySmall?.copyWith(color: c.textoTerciario),
            ),
          ],
        ),
      ),
    );
  }
}

class _CartaoDaEquipe extends StatelessWidget {
  const _CartaoDaEquipe({required this.equipe, required this.marcada, required this.aoEscolher});

  final EquipeDoDia equipe;
  final bool marcada;
  final VoidCallback aoEscolher;

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    return Material(
      color: c.superficie,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: marcada ? c.destaque : c.linha, width: marcada ? 2 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: aoEscolher,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(
            children: [
              Radio<String>(value: equipe.id),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(equipe.nome, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(equipe.resumo, style: TextStyle(color: c.textoSecundario)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Checagem extends StatelessWidget {
  const _Checagem({required this.ok, required this.texto});

  final bool ok;
  final String texto;

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(ok ? Icons.check_circle_rounded : Icons.info_outline_rounded, size: 20, color: ok ? c.ok : c.atencao),
          const SizedBox(width: 10),
          Expanded(child: Text(texto)),
        ],
      ),
    );
  }
}

/// Mensagem de erro com ação opcional.
class _Aviso extends StatelessWidget {
  const _Aviso({required this.texto, this.acao, required this.aoAgir});

  final String texto;
  final String? acao;
  final VoidCallback aoAgir;

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.perigo),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              texto,
              style: TextStyle(color: c.perigo, fontWeight: FontWeight.w600),
            ),
            if (acao case final a?) TextButton(onPressed: aoAgir, child: Text(a)),
          ],
        ),
      ),
    );
  }
}
