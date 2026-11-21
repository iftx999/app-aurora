import 'package:flutter/material.dart';

import '../../app/tema.dart';
import '../../dados/modelos/dia.dart';
import '../comum/botao_de_acao.dart';

class EscolhaDeMotivo {
  const EscolhaDeMotivo(this.motivoId, this.observacao);

  final String motivoId;
  final String? observacao;
}

/// Motivo de paralisar ou devolver (RN-22; protótipo `Motivo`): "Outro" e afins exigem observação.
class MotivoTela extends StatefulWidget {
  const MotivoTela({super.key, required this.titulo, required this.ajuda, required this.botao, required this.motivos});

  final String titulo;
  final String ajuda;
  final String botao;
  final List<MotivoDoCampo> motivos;

  static const maximoDeObservacao = 500;

  @override
  State<MotivoTela> createState() => _MotivoTelaState();
}

class _MotivoTelaState extends State<MotivoTela> {
  String? _motivo;
  final _observacao = TextEditingController();
  String? _erro;

  @override
  void dispose() {
    _observacao.dispose();
    super.dispose();
  }

  MotivoDoCampo? get _escolhido => widget.motivos.where((m) => m.id == _motivo).firstOrNull;

  void _confirmar() {
    final m = _escolhido;
    final obs = _observacao.text.trim();
    if (m == null) return setState(() => _erro = 'Escolha o motivo.');
    if (m.exigeObservacao && obs.isEmpty) return setState(() => _erro = 'Escreva a observação para "${m.nome}".');
    Navigator.of(context).pop(EscolhaDeMotivo(m.id, obs.isEmpty ? null : obs));
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
