import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../jornada/coleta_de_posicoes.dart';
import '../../jornada/controle_do_dia.dart';
import '../../sincronizacao/controle_da_fila.dart';
import '../hoje/hoje_tela.dart';
import '../jornada/jornada_tela.dart';

/// Depois de desbloquear: em jornada, a lista do dia; senão, "Iniciar jornada" (J8). Ao voltar para o app, envia a
/// fila e baixa as mudanças.
class InicioTela extends ConsumerStatefulWidget {
  const InicioTela({super.key});

  @override
  ConsumerState<InicioTela> createState() => _InicioTelaState();
}

class _InicioTelaState extends ConsumerState<InicioTela> {
  late final AppLifecycleListener _ciclo;

  @override
  void initState() {
    super.initState();
    _ciclo = AppLifecycleListener(
      onResume: () {
        ref.read(filaProvider.notifier).sincronizador.enviar();
        ref.read(controleDoDiaProvider.notifier).atualizar();
        ref.read(coletaProvider.notifier).retomar();
      },
    );
  }

  @override
  void dispose() {
    _ciclo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(filaProvider); // a fila começa a enviar assim que o app abre
    ref.watch(coletaProvider); // e a coleta de posições segue a jornada (RN-27)
    final emJornada = ref.watch(controleDoDiaProvider.select((d) => d.emJornada));
    return emJornada ? const HojeTela() : const JornadaTela();
  }
}

class TelaCarregando extends StatelessWidget {
  const TelaCarregando({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: CircularProgressIndicator()));
}
