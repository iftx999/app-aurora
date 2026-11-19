import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/dependencias.dart';
import '../../app/tema.dart';
import '../../autenticacao/estado_sessao.dart';
import '../../autenticacao/pin.dart';
import 'moldura.dart';

/// Criar o PIN (duas vezes) ou desbloquear com ele ou com a biometria (protótipo, tela 1).
class PinTela extends ConsumerStatefulWidget {
  const PinTela({super.key});

  @override
  ConsumerState<PinTela> createState() => _PinTelaState();
}

class _PinTelaState extends ConsumerState<PinTela> {
  String _pin = '';
  String? _primeiro;
  String? _erroLocal;
  bool _conferindo = false;

  Future<void> _digito(String d) async {
    if (_conferindo || _pin.length >= Pin.tamanho) {
      return;
    }
    setState(() {
      _pin += d;
      _erroLocal = null;
    });
    if (_pin.length == Pin.tamanho) {
      await _completo();
    }
  }

  void _apagar() {
    if (_pin.isNotEmpty) {
      setState(() => _pin = _pin.substring(0, _pin.length - 1));
    }
  }

  Future<void> _completo() async {
    final sessao = ref.read(sessaoProvider.notifier).sessao;
    final estado = ref.read(sessaoProvider);
    final pin = _pin;
    if (estado is CriarPin) {
      if (_primeiro == null) {
        final problema = Pin.problema(pin);
        setState(() {
          _pin = '';
          if (problema != null) {
            _erroLocal = problema;
          } else {
            _primeiro = pin;
          }
        });
        return;
      }
      if (_primeiro != pin) {
        setState(() {
          _pin = '';
          _primeiro = null;
          _erroLocal = 'Os PINs não conferem. Crie de novo.';
        });
        return;
      }
      setState(() => _conferindo = true);
      await sessao.criarPin(pin);
      return;
    }
    setState(() => _conferindo = true);
    await sessao.desbloquear(pin);
    if (mounted) {
      setState(() {
        _pin = '';
        _conferindo = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final estado = ref.watch(sessaoProvider);
    final criando = estado is CriarPin;
    final nome = switch (estado) {
      CriarPin(:final nome) || Bloqueada(:final nome) => nome,
      _ => '',
    };
    final ola = nome.isEmpty ? 'Olá.' : 'Olá, $nome.';
    final instrucao = criando
        ? (_primeiro == null ? '$ola Crie um PIN de 6 números para abrir o app.' : 'Digite o PIN de novo para confirmar.')
        : '$ola Digite o PIN para desbloquear.';
    final erro = _erroLocal ?? (estado is Bloqueada ? estado.erro : null);
    final restantes = estado is Bloqueada ? estado.tentativasRestantes : Pin.tentativas;
    final c = context.cores;
    return MolduraDeEntrada(
      titulo: 'Aurora Campo',
      subtitulo: instrucao,
      filhos: [
        Semantics(
          label: '${_pin.length} de ${Pin.tamanho} números digitados',
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < Pin.tamanho; i++)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 7),
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: c.destaque, width: 2),
                    color: i < _pin.length ? c.destaque : Colors.transparent,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (erro != null)
          Semantics(
            liveRegion: true,
            child: Text(
              estado is Bloqueada && restantes < Pin.tentativas
                  ? '$erro Restam $restantes ${restantes == 1 ? 'tentativa' : 'tentativas'}.'
                  : erro,
              style: TextStyle(color: c.perigo, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
          ),
        const SizedBox(height: 16),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
            childAspectRatio: 1.3,
            children: [
              for (final d in ['1', '2', '3', '4', '5', '6', '7', '8', '9']) _Tecla(d, () => _digito(d)),
              const SizedBox.shrink(),
              _Tecla('0', () => _digito('0')),
              _Tecla('⌫', _apagar, rotulo: 'Apagar', transparente: true),
            ],
          ),
        ),
        const SizedBox(height: 20),
        if (estado is Bloqueada && estado.biometria)
          SizedBox(
            width: 300,
            child: FilledButton.icon(
              onPressed: () => ref.read(sessaoProvider.notifier).sessao.desbloquearComBiometria(),
              icon: const Icon(Icons.fingerprint),
              label: const Text('Usar biometria'),
            ),
          ),
        if (estado is Bloqueada)
          TextButton(
            onPressed: () => ref.read(sessaoProvider.notifier).sessao.sair(),
            child: const Text('Esqueci o PIN: entrar de novo'),
          ),
      ],
      rodape: Text(
        'Sem sinal? O app funciona por até 7 dias desde o último contato com a empresa.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 13, color: c.textoSecundario, height: 1.5),
      ),
    );
  }
}

class _Tecla extends StatelessWidget {
  const _Tecla(this.texto, this.tocar, {this.rotulo, this.transparente = false});

  final String texto;
  final VoidCallback tocar;
  final String? rotulo;
  final bool transparente;

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    return Semantics(
      button: true,
      label: rotulo ?? 'Número $texto',
      excludeSemantics: true,
      child: Material(
        color: transparente ? Colors.transparent : c.superficie,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: tocar,
          child: Center(
            child: Text(texto, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600, color: c.texto)),
          ),
        ),
      ),
    );
  }
}
