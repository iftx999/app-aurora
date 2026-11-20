import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/dependencias.dart';
import '../autenticacao/estado_sessao.dart';
import 'sincronizador.dart';

/// Verdadeiro quando o servidor já tem a jornada aberta no celular (ou nenhuma está pendente); quem decide é o
/// controle do dia, que observa a fila (por isso a fila não lê o dia direto).
final posicoesLiberadasProvider = NotifierProvider<PosicoesLiberadas, bool>(PosicoesLiberadas.new);

class PosicoesLiberadas extends Notifier<bool> {
  @override
  bool build() => false;

  void definir(bool liberadas) => state = liberadas;
}

final filaProvider = NotifierProvider<ControleDaFila, EstadoDaFila>(ControleDaFila.new);

/// Liga o [Sincronizador] às telas e à sessão (J10).
class ControleDaFila extends Notifier<EstadoDaFila> {
  late Sincronizador sincronizador;

  @override
  EstadoDaFila build() {
    final s = Sincronizador(
      armazem: ref.watch(armazemProvider),
      api: ref.watch(apiCampoProvider),
      arquivos: ref.watch(arquivosDeFotoProvider),
      agora: ref.watch(relogioProvider),
    );
    s
      ..aoMudar = ((novo) {
        if (ref.mounted) state = novo;
      })
      ..aoRevogar = (() => ref.read(sessaoProvider.notifier).sessao.revogar())
      // Jornada iniciada sem sinal: as posições esperam o início chegar ao servidor.
      ..podeEnviarPosicoes = (() => ref.read(posicoesLiberadasProvider));
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
