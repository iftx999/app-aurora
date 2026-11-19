import 'package:flutter/material.dart';

import '../../app/tema.dart';

/// Fundo das telas de entrada: sempre no tema escuro da marca (protótipo, tela 1).
class MolduraDeEntrada extends StatelessWidget {
  const MolduraDeEntrada({super.key, required this.titulo, this.subtitulo, required this.filhos, this.rodape});

  final String titulo;
  final String? subtitulo;
  final List<Widget> filhos;
  final Widget? rodape;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: temaAurora(Brightness.dark),
      child: Builder(
        builder: (context) {
          final c = context.cores;
          return Scaffold(
            body: SafeArea(
              child: LayoutBuilder(
                builder: (context, limites) => SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: limites.maxHeight - 72),
                    child: Column(
                      children: [
                        const LogoAurora(),
                        const SizedBox(height: 12),
                        Text(titulo,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                        if (subtitulo != null) ...[
                          const SizedBox(height: 8),
                          Text(subtitulo!,
                              textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: c.textoSecundario)),
                        ],
                        const SizedBox(height: 28),
                        ...filhos,
                        if (rodape != null) ...[const SizedBox(height: 24), rodape!],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class LogoAurora extends StatelessWidget {
  const LogoAurora({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Aurora',
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const SweepGradient(
            startAngle: 3.665,
            colors: [Color(0xFF1ACBD8), Color(0xFF2C9AEB), Color(0xFF4AD7BC), Color(0xFF1ACBD8)],
          ),
        ),
      ),
    );
  }
}

/// Aviso ou erro em texto, para leitores de tela também.
class Aviso extends StatelessWidget {
  const Aviso(this.texto, {super.key, this.erro = false});

  final String texto;
  final bool erro;

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    final cor = erro ? c.perigo : c.atencao;
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          border: Border.all(color: cor),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(erro ? Icons.error_outline : Icons.info_outline, color: cor),
            const SizedBox(width: 10),
            Expanded(child: Text(texto, style: TextStyle(color: c.texto))),
          ],
        ),
      ),
    );
  }
}
