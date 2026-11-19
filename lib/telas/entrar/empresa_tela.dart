import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/dependencias.dart';
import 'moldura.dart';

/// Primeiro uso: código da empresa (o mesmo da tela web, ADR 0027).
class EmpresaTela extends ConsumerStatefulWidget {
  const EmpresaTela({super.key});

  @override
  ConsumerState<EmpresaTela> createState() => _EmpresaTelaState();
}

class _EmpresaTelaState extends ConsumerState<EmpresaTela> {
  final _codigo = TextEditingController();
  String? _erro;

  @override
  void dispose() {
    _codigo.dispose();
    super.dispose();
  }

  Future<void> _continuar() async {
    try {
      await ref.read(sessaoProvider.notifier).sessao.informarEmpresa(_codigo.text);
    } on FormatException {
      setState(() => _erro = 'Confira o código: letras minúsculas, números e hífen.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MolduraDeEntrada(
      titulo: 'Aurora Campo',
      subtitulo: 'Informe o código da empresa. Ele vem com o celular ou com o seu gestor.',
      filhos: [
        TextField(
          controller: _codigo,
          autofocus: true,
          autocorrect: false,
          textInputAction: TextInputAction.go,
          onSubmitted: (_) => _continuar(),
          decoration: InputDecoration(labelText: 'Código da empresa', errorText: _erro),
        ),
        const SizedBox(height: 16),
        SizedBox(width: double.infinity, child: FilledButton(onPressed: _continuar, child: const Text('Continuar'))),
      ],
    );
  }
}
