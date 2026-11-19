import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/dependencias.dart';
import '../autenticacao/estado_sessao.dart';
import 'sincronizador.dart';

final filaProvider = NotifierProvider<ControleDaFila, EstadoDaFila>(ControleDaFila.new);

/// Liga o [Sincronizador] às telas e à sessão (J10).
class ControleDaFila extends Notifier<EstadoDaFila> {
  late Sincronizador sincronizador;

  @override
  EstadoDaFila build() {
    final s = Sincronizador(
      armazem: ref.watch(armazemProvider),
      api: ref.watch(apiCampoProvider),
      agora: ref.watch(relogioProvider),
    );
    s
      ..aoMudar = ((novo) {
        if (ref.mounted) state = novo;
      })
      ..aoRevogar = (() => ref.read(sessaoProvider.notifier).sessao.revogar());
    sincronizador = s;
    ref.listen(sessaoProvider, (anterior, novo) {
      final saiu = anterior is Desbloqueada || anterior is Bloqueada;
      if (saiu && (novo is SemLogin || novo is SemEmpresa || novo is Revogada)) ref.invalidateSelf();
    });
    final controleDaSessao = ref.read(sessaoProvider.notifier)..enviarFila = s.enviarEParar;
    ref.onDispose(() {
      s.parar();
      if (controleDaSessao.enviarFila == s.enviarEParar) controleDaSessao.enviarFila = null;
    });
    // Ao abrir o app: o que ficou na fila sai assim que der.
    Future.microtask(() async {
      await s.recontar();
      await s.enviar();
    });
    return const EstadoDaFila();
  }
}
