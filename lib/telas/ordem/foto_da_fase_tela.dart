import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/tema.dart';
import '../../dados/modelos/evento.dart';
import '../../jornada/controle_do_dia.dart';
import '../comum/botao_de_acao.dart';
import '../comum/fotos_da_acao.dart';

/// Iniciar ou retomar a OS com foto (ADR 0053): a ação só entra na fila com ao menos uma foto. Paralisar e devolver
/// pedem a foto na tela do motivo.
class FotoDaFaseTela extends ConsumerStatefulWidget {
  const FotoDaFaseTela({super.key, required this.osId, required this.acao})
    : assert(acao == AcaoDeCampo.iniciar || acao == AcaoDeCampo.retomar);

  final String osId;
  final AcaoDeCampo acao;

  @override
  ConsumerState<FotoDaFaseTela> createState() => _FotoDaFaseTelaState();
}

class _FotoDaFaseTelaState extends ConsumerState<FotoDaFaseTela> {
  late final FotosDaAcao _fotos;
  String? _erro;
  bool _salvando = false;

  bool get _iniciar => widget.acao == AcaoDeCampo.iniciar;

  @override
  void initState() {
    super.initState();
    _fotos = FotosDaAcao(ref);
  }

  @override
  void dispose() {
    _fotos.descartar();
    super.dispose();
  }

  Future<void> _tirar() async {
    if (await _fotos.tirar() && mounted) setState(() => _erro = null);
  }

  Future<void> _confirmar() async {
    if (_fotos.lista.isEmpty) {
      return setState(() => _erro = 'Tire pelo menos uma foto para ${_iniciar ? 'iniciar' : 'retomar'} a OS.');
    }
    setState(() => _salvando = true);
    await ref
        .read(controleDoDiaProvider.notifier)
        .registrar(widget.osId, widget.acao, fotos: _fotos.paraAFila(widget.osId));
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    final texto = Theme.of(context).textTheme;
    final ordem = ref
        .watch(controleDoDiaProvider.select((d) => d.pacote?.ordens.where((o) => o.id == widget.osId)))
        ?.firstOrNull;
    final rotulo = _iniciar ? 'Iniciar' : 'Retomar';
    return Scaffold(
      appBar: AppBar(title: Text('$rotulo OS ${ordem?.numero ?? ''}')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          if (ordem != null) ...[
            Text(ordem.servicoNome, style: texto.titleLarge),
            const SizedBox(height: 2),
            Text(ordem.endereco, style: TextStyle(color: c.textoSecundario)),
            const SizedBox(height: 20),
          ],
          CampoDeFotos(
            titulo: _iniciar ? 'Foto do local antes de começar' : 'Foto da situação ao retomar',
            ajuda: _iniciar
                ? 'Fachada, calçada ou PV como estão agora. Serve de prova do estado antes do serviço.'
                : 'Mostre que o motivo da paralisação foi resolvido.',
            fotos: _fotos.lista,
            aoTirar: _tirar,
            aoRemover: (f) => setState(() => _fotos.remover(f)),
          ),
          if (_erro case final e?) ...[
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: Text(
                e,
                style: TextStyle(color: c.perigo, fontWeight: FontWeight.w600),
              ),
            ),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: BotaoDeAcao(
                  aoConfirmar: _salvando ? null : _confirmar,
                  icone: Icons.play_arrow_rounded,
                  rotulo: '$rotulo OS',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'A foto fica guardada no celular, criptografada, e vai para o servidor junto com a ação.',
            textAlign: TextAlign.center,
            style: texto.bodySmall?.copyWith(color: c.textoTerciario),
          ),
        ],
      ),
    );
  }
}
