import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/tema.dart';
import '../../dados/modelos/dia.dart';
import '../../dados/modelos/foto.dart';
import '../comum/botao_de_acao.dart';
import '../comum/fotos_da_acao.dart';

class EscolhaDeMotivo {
  const EscolhaDeMotivo(this.motivoId, this.observacao, {this.fotos = const []});

  final String motivoId;
  final String? observacao;

  /// ADR 0053: fotos da paralisação ou da devolução, prontas para a fila.
  final List<FotoDaOs> fotos;
}

/// A foto pedida junto do motivo (ADR 0053).
class FotoDoMotivo {
  const FotoDoMotivo({required this.osId, required this.titulo, required this.ajuda, required this.verbo});

  final String osId;
  final String titulo;
  final String ajuda;

  /// "paralisar", "devolver".
  final String verbo;
}

/// Motivo de paralisar ou devolver (RN-22; protótipo `Motivo`): "Outro" e afins exigem observação; com [foto], exige
/// ao menos uma foto (ADR 0053).
class MotivoTela extends ConsumerStatefulWidget {
  const MotivoTela({
    super.key,
    required this.titulo,
    required this.ajuda,
    required this.botao,
    required this.motivos,
    this.foto,
  });

  final String titulo;
  final String ajuda;
  final String botao;
  final List<MotivoDoCampo> motivos;
  final FotoDoMotivo? foto;

  static const maximoDeObservacao = 500;

  @override
  ConsumerState<MotivoTela> createState() => _MotivoTelaState();
}

class _MotivoTelaState extends ConsumerState<MotivoTela> {
  String? _motivo;
  final _observacao = TextEditingController();
  late final FotosDaAcao _fotos;
  String? _erro;

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

  MotivoDoCampo? get _escolhido => widget.motivos.where((m) => m.id == _motivo).firstOrNull;

  void _confirmar() {
    final m = _escolhido;
    final obs = _observacao.text.trim();
    if (m == null) return setState(() => _erro = 'Escolha o motivo.');
    if (m.exigeObservacao && obs.isEmpty) return setState(() => _erro = 'Escreva a observação para "${m.nome}".');
    final foto = widget.foto;
    if (foto != null && _fotos.lista.isEmpty) {
      return setState(() => _erro = 'Tire pelo menos uma foto para ${foto.verbo} a OS.');
    }
    Navigator.of(context).pop(
      EscolhaDeMotivo(m.id, obs.isEmpty ? null : obs, fotos: foto == null ? const [] : _fotos.paraAFila(foto.osId)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    final exige = _escolhido?.exigeObservacao ?? false;
    return Scaffold(
      appBar: AppBar(title: Text(widget.titulo)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Text(widget.ajuda, style: TextStyle(color: c.textoSecundario)),
          const SizedBox(height: 16),
          if (widget.motivos.isEmpty)
            const Text('Nenhum motivo cadastrado para esta ação. Fale com o gestor de serviços.')
          else
            RadioGroup<String>(
              groupValue: _motivo,
              onChanged: (v) => setState(() {
                _motivo = v;
                _erro = null;
              }),
              child: Column(
                children: [
                  for (final m in widget.motivos)
                    RadioListTile<String>(
                      value: m.id,
                      title: Text(m.nome),
                      contentPadding: EdgeInsets.zero,
                      minTileHeight: 56,
                    ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          TextField(
            controller: _observacao,
            maxLength: MotivoTela.maximoDeObservacao,
            minLines: 2,
            maxLines: 5,
            decoration: InputDecoration(labelText: exige ? 'Observação (obrigatória)' : 'Observação (opcional)'),
          ),
          if (widget.foto case final f?) ...[
            const SizedBox(height: 8),
            CampoDeFotos(
              titulo: f.titulo,
              ajuda: f.ajuda,
              fotos: _fotos.lista,
              aoTirar: _tirar,
              aoRemover: (foto) => setState(() => _fotos.remover(foto)),
            ),
          ],
          if (_erro case final e?)
            Semantics(
              liveRegion: true,
              child: Text(
                e,
                style: TextStyle(color: c.perigo, fontWeight: FontWeight.w600),
              ),
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: BotaoDeAcao(aoConfirmar: widget.motivos.isEmpty ? null : _confirmar, rotulo: widget.botao),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
