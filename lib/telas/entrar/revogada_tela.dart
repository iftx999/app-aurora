import 'package:flutter/material.dart';

import '../../app/tema.dart';
import 'moldura.dart';

/// Celular bloqueado pelo administrador (J13; protótipo, tela 8).
class RevogadaTela extends StatelessWidget {
  const RevogadaTela({super.key});

  @override
  Widget build(BuildContext context) {
    return MolduraDeEntrada(
      titulo: 'Este celular foi bloqueado',
      subtitulo: 'O administrador bloqueou o acesso a partir deste aparelho. O que estava na fila foi enviado e os '
          'dados das OS foram apagados.',
      filhos: [
        Builder(
          builder: (context) => Text(
            'Para voltar a trabalhar, peça um novo celular ao seu gestor.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: context.cores.texto, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}
