import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/dependencias.dart';
import '../../app/tema.dart';
import '../../dados/modelos/dia.dart';
import '../../dados/modelos/evento.dart';
import '../../jornada/controle_do_dia.dart';
import '../../nucleo/datas.dart';
import '../../sincronizacao/controle_da_fila.dart';
import '../comum/botao_de_acao.dart';
import '../comum/navegar.dart';
import 'encerrar_tela.dart';
import 'motivo_tela.dart';

void abrirOrdem(BuildContext context, OrdemDoDia ordem) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => OrdemTela(osId: ordem.id)));

/// A OS (J9; protótipo `Ordem`): dados, registro das ações e o que dá para fazer na situação atual.
class OrdemTela extends ConsumerWidget {
  const OrdemTela({super.key, required this.osId});

  final String osId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pacote = ref.watch(controleDoDiaProvider.select((d) => d.pacote));
    final ordem = pacote?.ordens.where((o) => o.id == osId).firstOrNull;
    final c = context.cores;
    final texto = Theme.of(context).textTheme;

    ref.listen(controleDoDiaProvider.select((d) => d.erro), (_, erro) {
      if (erro == null) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(erro)));
      ref.read(controleDoDiaProvider.notifier).dispensarErro();
    });

    if (pacote == null || ordem == null) {
      // A OS saiu do pacote (cancelada ou passada para outra equipe, 10.9.5).
      return Scaffold(
        appBar: AppBar(),
        body: const Padding(padding: EdgeInsets.all(24), child: Text('Esta OS não está mais na sua lista de hoje.')),
      );
    }
    final agora = ref.read(relogioProvider)();

    Widget campo(String rotulo, String valor) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(rotulo, style: texto.labelLarge?.copyWith(color: c.textoSecundario)),
          const SizedBox(height: 2),
          Text(valor, style: texto.bodyLarge),
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(title: Text('OS ${ordem.numero}')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Text(
            _situacao(ordem.status),
            style: texto.labelLarge?.copyWith(color: c.destaque, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(ordem.servicoNome, style: texto.headlineSmall),
          const SizedBox(height: 4),
          Text(
            'Prioridade ${_prioridade(ordem.prioridade)} · prazo ${prazo(ordem.prazo, agora)}',
            style: TextStyle(color: ordem.atrasada ? c.perigo : c.textoSecundario),
          ),
          const SizedBox(height: 20),
          campo(ordem.noTrecho ? 'Trecho' : 'Endereço', ordem.endereco),
          if (ordem.matricula case final m?) campo('Matrícula', m),
          campo('Previsto', '${_numero(ordem.quantidadePrevista)} ${ordem.unidadeMedida}'),
          if (ordem.instrucoes case final i? when i.trim().isNotEmpty) campo('Instruções', i),
          _Registro(osId: osId),
          const SizedBox(height: 16),
          ..._acoes(context, ref, pacote, ordem),
          if (ordem.status == StatusOrdem.programada && ordem.avisoDeChegada) ...[
            const SizedBox(height: 10),
            if (ordem.avisadoEm case final avisado?)
              Text(
                'Morador avisado às ${hora(avisado.toLocal())}.',
                textAlign: TextAlign.center,
                style: TextStyle(color: c.textoSecundario),
              )
            else
              OutlinedButton.icon(
                onPressed: () => _avisarChegada(context, ref, ordem),
                icon: const Icon(Icons.sms_rounded),
                label: const Text('Estou chegando'),
              ),
          ],
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => navegar(context, ordem),
            icon: const Icon(Icons.navigation_rounded),
            label: const Text('Navegar'),
          ),
        ],
      ),
    );
  }

  /// ADR 0052: escolhe em quanto tempo chega e pede o SMS ao morador (o número fica no servidor).
  Future<void> _avisarChegada(BuildContext context, WidgetRef ref, OrdemDoDia ordem) async {
    final minutos = await showDialog<int>(
      context: context,
      builder: (contexto) => SimpleDialog(
        title: const Text('Avisar o morador'),
        contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 16),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text('O morador recebe um SMS de que a equipe está a caminho. Você chega em cerca de:'),
          ),
          for (final m in const [5, 10, 15, 20, 30])
            SimpleDialogOption(
              onPressed: () => Navigator.of(contexto).pop(m),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Align(alignment: Alignment.centerLeft, child: Text('$m minutos')),
              ),
            ),
        ],
      ),
    );
    if (minutos == null || !context.mounted) return;
    final mensagem = await ref.read(controleDoDiaProvider.notifier).avisarChegada(ordem.id, minutos);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(mensagem)));
  }

  List<Widget> _acoes(BuildContext context, WidgetRef ref, PacoteDoDia pacote, OrdemDoDia ordem) {
    final controle = ref.read(controleDoDiaProvider.notifier);
    final pode = {for (final a in AcaoDeCampo.values) a: a.destino(ordem.status) != null};
    Future<void> comMotivo(AcaoDeCampo acao, String tipo, String titulo, String ajuda) async {
      final escolha = await Navigator.of(context).push<EscolhaDeMotivo>(
        MaterialPageRoute(
          builder: (_) => MotivoTela(
            titulo: '$titulo OS ${ordem.numero}',
            ajuda: ajuda,
            botao: titulo,
            motivos: pacote.motivosPara(tipo, ordem),
          ),
        ),
      );
      if (escolha != null) {
        await controle.registrar(ordem.id, acao, motivoId: escolha.motivoId, observacao: escolha.observacao);
      }
    }

    final principal = switch (ordem.status) {
      StatusOrdem.programada => BotaoDeAcao(
        aoConfirmar: () => controle.registrar(ordem.id, AcaoDeCampo.iniciar),
        icone: Icons.play_arrow_rounded,
        rotulo: 'Iniciar OS',
      ),
      StatusOrdem.emExecucao => FilledButton.icon(
        onPressed: () =>
            Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => EncerrarTela(osId: ordem.id))),
        icon: const Icon(Icons.task_alt_rounded),
        label: const Text('Encerrar OS'),
      ),
      StatusOrdem.paralisada => BotaoDeAcao(
        aoConfirmar: () => controle.registrar(ordem.id, AcaoDeCampo.retomar),
        icone: Icons.play_arrow_rounded,
        rotulo: 'Retomar OS',
      ),
      _ => null,
    };
    return [
      ?principal,
      if (pode[AcaoDeCampo.paralisar]!) ...[
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: () => comMotivo(
            AcaoDeCampo.paralisar,
            'PARALISACAO',
            'Paralisar',
            'O tempo parado fica separado do tempo de execução.',
          ),
          child: const Text('Paralisar'),
        ),
      ],
      if (pode[AcaoDeCampo.devolver]!) ...[
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: () => comMotivo(
            AcaoDeCampo.devolver,
            'DEVOLUCAO',
            'Devolver',
            'A OS volta para o programador decidir (reprogramar ou cancelar).',
          ),
          child: const Text('Devolver'),
        ),
      ],
    ];
  }

  static String _situacao(StatusOrdem s) => switch (s) {
    StatusOrdem.programada => 'Programada',
    StatusOrdem.emExecucao => 'Em execução',
    StatusOrdem.paralisada => 'Paralisada',
    StatusOrdem.devolvida => 'Devolvida',
    StatusOrdem.encerrada => 'Encerrada',
    StatusOrdem.cancelada => 'Cancelada',
    StatusOrdem.planejada => 'Planejada',
  };

  static String _prioridade(Prioridade p) => switch (p) {
    Prioridade.emergencial => 'emergencial',
    Prioridade.alta => 'alta',
    Prioridade.media => 'média',
    Prioridade.baixa => 'baixa',
  };

  static String _numero(num n) => (n == n.truncate() ? n.toInt().toString() : n.toString()).replaceAll('.', ',');
}

/// "Início 14:05 · enviado", das ações desta OS que ainda estão no celular.
class _Registro extends ConsumerStatefulWidget {
  const _Registro({required this.osId});

  final String osId;

  @override
  ConsumerState<_Registro> createState() => _RegistroState();
}

class _RegistroState extends ConsumerState<_Registro> {
  List<EventoNaFila> _eventos = const [];

  @override
  void initState() {
    super.initState();
    _ler();
  }

  Future<void> _ler() async {
    final todos = await ref.read(armazemProvider).eventos();
    if (mounted) setState(() => _eventos = todos.where((e) => e.evento.osId == widget.osId).toList());
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(filaProvider.select((f) => f.versao), (_, _) => _ler());
    if (_eventos.isEmpty) return const SizedBox.shrink();
    final c = context.cores;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Registro', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: c.textoSecundario)),
        const SizedBox(height: 4),
        for (final e in _eventos)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              '${e.evento.acao.rotulo} ${hora(e.evento.ocorridoEm)} · ${_envio(e)}',
              style: TextStyle(color: e.situacao.avisar ? c.perigo : c.texto),
            ),
          ),
        const SizedBox(height: 8),
      ],
    );
  }

  static String _envio(EventoNaFila e) => switch (e.situacao) {
    SituacaoDoEnvio.pendente => 'na fila',
    SituacaoDoEnvio.aplicado || SituacaoDoEnvio.repetido => 'enviado',
    SituacaoDoEnvio.aguardando => 'enviado, esperando o anterior',
    SituacaoDoEnvio.conflito => 'enviado, em conflito: o programador vai decidir',
    SituacaoDoEnvio.superado => 'não valeu: a programação mudou',
    SituacaoDoEnvio.rejeitado => 'recusado: ${e.mensagem ?? ''}',
  };
}
