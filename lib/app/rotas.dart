import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../autenticacao/estado_sessao.dart';
import '../telas/entrar/empresa_tela.dart';
import '../telas/entrar/entrar_tela.dart';
import '../telas/entrar/pin_tela.dart';
import '../telas/entrar/revogada_tela.dart';
import '../telas/inicio/inicio_tela.dart';
import 'dependencias.dart';

/// Rotas: a entrada é decidida pela sessão; nenhuma tela de trabalho abre sem o app desbloqueado.
final rotasProvider = Provider<GoRouter>((ref) {
  final mudou = ValueNotifier(0);
  ref.listen(sessaoProvider, (_, _) => mudou.value++);
  ref.onDispose(mudou.dispose);
  return GoRouter(
    initialLocation: '/inicio',
    refreshListenable: mudou,
    redirect: (context, estado) {
      final destino = switch (ref.read(sessaoProvider)) {
        Carregando() => '/carregando',
        SemEmpresa() => '/empresa',
        SemLogin() => '/entrar',
        CriarPin() || Bloqueada() => '/pin',
        Revogada() => '/bloqueado',
        Desbloqueada() => null,
      };
      if (destino != null) {
        return estado.matchedLocation == destino ? null : destino;
      }
      const entrada = ['/carregando', '/empresa', '/entrar', '/pin', '/bloqueado'];
      return entrada.contains(estado.matchedLocation) ? '/inicio' : null;
    },
    routes: [
      GoRoute(path: '/carregando', builder: (_, _) => const TelaCarregando()),
      GoRoute(path: '/empresa', builder: (_, _) => const EmpresaTela()),
      GoRoute(path: '/entrar', builder: (_, _) => const EntrarTela()),
      GoRoute(path: '/pin', builder: (_, _) => const PinTela()),
      GoRoute(path: '/bloqueado', builder: (_, _) => const RevogadaTela()),
      GoRoute(path: '/inicio', builder: (_, _) => const InicioTela()),
    ],
  );
});
