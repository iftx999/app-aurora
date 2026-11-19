import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../jornada/controle_do_dia.dart';
import '../hoje/hoje_tela.dart';
import '../jornada/jornada_tela.dart';

/// Depois de desbloquear: em jornada, a lista do dia; senão, "Iniciar jornada" (J8).
class InicioTela extends ConsumerWidget {
  const InicioTela({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final emJornada = ref.watch(controleDoDiaProvider.select((d) => d.emJornada));
    return emJornada ? const HojeTela() : const JornadaTela();
  }
}

class TelaCarregando extends StatelessWidget {
  const TelaCarregando({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: CircularProgressIndicator()));
}
