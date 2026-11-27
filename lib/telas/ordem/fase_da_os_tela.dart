import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/tema.dart';
import '../../dados/modelos/evento.dart';
import '../../jornada/controle_do_dia.dart';
import '../comum/botao_de_acao.dart';
import '../comum/fotos_da_acao.dart';
import 'motivo_tela.dart';

/// Iniciar ou retomar a OS com o que o serviço exige (ADR 0053): ao menos uma foto e a observação. A ação só entra na
/// fila com as duas. Paralisar e devolver pedem foto e observação na tela do motivo.
class FaseDaOsTela extends ConsumerStatefulWidget {
  const FaseDaOsTela({super.key, required this.osId, required this.acao})
    : assert(acao == AcaoDeCampo.iniciar || acao == AcaoDeCampo.retomar);

  final String osId;
  final AcaoDeCampo acao;

  @override
  ConsumerState<FaseDaOsTela> createState() => _FaseDaOsTelaState();
}

class _FaseDaOsTelaState extends ConsumerState<FaseDaOsTela> {
  late final FotosDaAcao _fotos;
  final _observacao = TextEditingController();
  String? _erro;
  bool _salvando = false;

  bool get _iniciar => widget.acao == AcaoDeCampo.iniciar;
  String get _verbo => _iniciar ? 'iniciar' : 'retomar';

  @override
  void initState() {
    super.initState();
    _fotos = FotosDaAcao(ref);
  }

  @override
  void dispose() {
    _observacao.dispose();
    _fotos.descartar();
    super.dispose();
  }

  Future<void> _tirar() async {
    if (await _fotos.tirar() && mounted) setState(() => _erro = null);
  }

  Future<void> _confirmar(bool exigeFoto, bool exigeObservacao) async {
    final obs = _observacao.text.trim();
    if (exigeFoto && _fotos.lista.isEmpty) return setState(() => _erro = 'Tire pelo menos uma foto para $_verbo a OS.');
    if (exigeObservacao && obs.isEmpty) return setState(() => _erro = 'Escreva a observação para $_verbo a OS.');
    setState(() => _salvando = true);
    await ref
        .read(controleDoDiaProvider.notifier)
        .registrar(
          widget.osId,
          widget.acao,
          observacao: obs.isEmpty ? null : obs,
          fotos: _fotos.paraAFila(widget.osId),
        );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    final texto = Theme.of(context).textTheme;
    final ordem = ref
        .watch(controleDoDiaProvider.select((d) => d.pacote?.ordens.where((o) => o.id == widget.osId)))
        ?.firstOrNull;
    final exigeFoto = ordem?.exigeFoto(widget.acao) ?? false;
    final exigeObservacao = ordem?.exigeObservacao(widget.acao) ?? false;
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
          if (exigeFoto) ...[
            CampoDeFotos(
              titulo: _iniciar ? 'Foto do local antes de começar' : 'Foto da situação ao retomar',
              ajuda: _iniciar
                  ? 'Fachada, calçada ou PV como estão agora. Serve de prova do estado antes do serviço.'
                  : 'Mostre que o motivo da paralisação foi resolvido.',
              fotos: _fotos.lista,
              aoTirar: _tirar,
              aoRemover: (f) => setState(() => _fotos.remover(f)),
            ),
            const SizedBox(height: 16),
          ],
          TextField(
            controller: _observacao,
            maxLength: MotivoTela.maximoDeObservacao,
            minLines: 2,
            maxLines: 5,
            onChanged: (_) {
              if (_erro != null) setState(() => _erro = null);
            },
            decoration: InputDecoration(
              labelText: exigeObservacao ? 'Observação (obrigatória)' : 'Observação (opcional)',
              hintText: _iniciar ? 'Ex.: calçada quebrada, PV com tampa solta' : 'Ex.: chuva parou, material chegou',
              helperText: 'Descreva o local e o serviço; não escreva dados do morador.',
              helperMaxLines: 2,
            ),
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
                  aoConfirmar: _salvando ? null : () => _confirmar(exigeFoto, exigeObservacao),
                  icone: Icons.play_arrow_rounded,
                  rotulo: '$rotulo OS',
                ),
              ),
            ],
          ),
          if (exigeFoto) ...[
            const SizedBox(height: 10),
            Text(
              'A foto fica guardada no celular, criptografada, e vai para o servidor junto com a ação.',
              textAlign: TextAlign.center,
              style: texto.bodySmall?.copyWith(color: c.textoTerciario),
            ),
          ],
        ],
      ),
    );
  }
}
