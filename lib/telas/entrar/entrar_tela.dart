import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/dependencias.dart';
import '../../app/tema.dart';
import '../../autenticacao/estado_sessao.dart';
import '../../dados/api/erros.dart';
import 'moldura.dart';

/// Login com a conta da empresa no navegador do celular (Keycloak, PKCE). Precisa de sinal.
class EntrarTela extends ConsumerStatefulWidget {
  const EntrarTela({super.key});

  @override
  ConsumerState<EntrarTela> createState() => _EntrarTelaState();
}

class _EntrarTelaState extends ConsumerState<EntrarTela> {
  bool _entrando = false;
  String? _erro;

  Future<void> _entrar() async {
    setState(() {
      _entrando = true;
      _erro = null;
    });
    try {
      await ref.read(sessaoProvider.notifier).sessao.entrar();
    } on SemConexao {
      _falhou('Sem conexão com a Aurora. O primeiro login precisa de sinal.');
    } on ErroDaApi catch (e) {
      _falhou(e.mensagem);
    } on Exception {
      _falhou('Não deu para entrar. Confira o sinal e tente de novo.');
    }
  }

  void _falhou(String mensagem) {
    if (mounted) {
      setState(() {
        _entrando = false;
        _erro = mensagem;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final estado = ref.watch(sessaoProvider);
    final empresa = estado is SemLogin ? estado.codigoEmpresa : '';
    final aviso = estado is SemLogin ? estado.aviso : null;
    return MolduraDeEntrada(
      titulo: 'Aurora Campo',
      subtitulo: 'Empresa: $empresa',
      filhos: [
        if (aviso != null) ...[Aviso(aviso), const SizedBox(height: 16)],
        if (_erro != null) ...[Aviso(_erro!, erro: true), const SizedBox(height: 16)],
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _entrando ? null : _entrar,
            icon: _entrando
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.login),
            label: const Text('Entrar com a conta da empresa'),
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _entrando ? null : () => ref.read(sessaoProvider.notifier).sessao.trocarEmpresa(),
          child: const Text('Trocar empresa'),
        ),
      ],
      rodape: Text(
        'Depois do login, você cria um PIN de 6 números para abrir o app, inclusive sem sinal.',
        textAlign: TextAlign.center,
        style: TextStyle(color: context.cores.textoSecundario, fontSize: 13),
      ),
    );
  }
}
