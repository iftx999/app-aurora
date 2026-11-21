import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/modo_luva.dart';
import '../../app/tema.dart';

/// Botão das ações da OS (iniciar, retomar, paralisar, devolver, encerrar). No modo luva (ADR 0051), a ação só sai
/// segurando o botão até a barra encher ([segurar]); um toque rápido só lembra como fazer.
class BotaoDeAcao extends ConsumerStatefulWidget {
  const BotaoDeAcao({super.key, required this.rotulo, required this.aoConfirmar, this.icone});

  final String rotulo;
  final VoidCallback? aoConfirmar;
  final IconData? icone;

  static const segurar = Duration(milliseconds: 900);

  @override
  ConsumerState<BotaoDeAcao> createState() => _BotaoDeAcaoState();
}

class _BotaoDeAcaoState extends ConsumerState<BotaoDeAcao> with SingleTickerProviderStateMixin {
  late final AnimationController _progresso = AnimationController(vsync: this, duration: BotaoDeAcao.segurar)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        _confirmado = true;
        HapticFeedback.heavyImpact();
        _progresso.reset();
        widget.aoConfirmar?.call();
      }
    });

  /// Já confirmou neste toque: soltar o dedo não mostra a dica.
  bool _confirmado = false;

  @override
  void dispose() {
    _progresso.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final luva = ref.watch(modoLuvaProvider);
    final acao = widget.aoConfirmar;
    final conteudo = widget.icone == null
        ? Text(luva ? _segure(widget.rotulo) : widget.rotulo)
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icone),
              const SizedBox(width: 8),
              Flexible(child: Text(luva ? _segure(widget.rotulo) : widget.rotulo)),
            ],
          );
    if (!luva || acao == null) {
      return FilledButton(onPressed: acao, child: conteudo);
    }
    final c = context.cores;
    return Semantics(
      button: true,
      label: widget.rotulo,
      hint: 'Modo luva: toque duas vezes e segure',
      onLongPress: acao,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) {
          _confirmado = false;
          _progresso.forward();
        },
        onTapUp: (_) => _soltar(avisar: true),
        // Cancelado (ex.: o dedo rolou a tela): só desfaz a barra.
        onTapCancel: _soltar,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Só o desenho: o gesto é do detector acima (o botão ganharia a disputa do toque).
            IgnorePointer(
              child: FilledButton(onPressed: () {}, child: conteudo),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: AnimatedBuilder(
                    animation: _progresso,
                    builder: (_, _) => Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: _progresso.value,
                        heightFactor: 1,
                        child: ColoredBox(color: c.sobreDestaque.withValues(alpha: 0.28)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _soltar({bool avisar = false}) {
    if (_confirmado) return;
    _progresso.reverse();
    if (avisar && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Modo luva: segure o botão até a barra encher.')));
    }
  }
}

/// "Iniciar OS" → "Segure para iniciar OS".
String _segure(String rotulo) =>
    rotulo.isEmpty ? rotulo : 'Segure para ${rotulo[0].toLowerCase()}${rotulo.substring(1)}';
