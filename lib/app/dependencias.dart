import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../autenticacao/biometria.dart';
import '../autenticacao/cofre.dart';
import '../autenticacao/estado_sessao.dart';
import '../autenticacao/provedor_identidade.dart';
import '../autenticacao/sessao.dart';
import '../dados/api/api_campo.dart';
import '../dados/api/cliente_api.dart';
import '../dados/local/armazem_do_dia.dart';
import '../dados/localizacao.dart';
import '../nucleo/configuracao.dart';

/// Peças do app; os testes trocam por versões falsas com `overrides`.
final configuracaoProvider = Provider<Configuracao>((ref) => Configuracao.doAmbiente());
final cofreProvider = Provider<Cofre>((ref) => CofreSeguro());
final identidadeProvider = Provider<ProvedorIdentidade>((ref) => ProvedorAppAuth(ref.watch(configuracaoProvider)));
final armazemProvider = Provider<ArmazemDoDia>((ref) => ArmazemSqlCipher(ref.watch(cofreProvider)));
final localizacaoProvider = Provider<Localizacao>((ref) => LocalizacaoDoAparelho());
final relogioProvider = Provider<DateTime Function()>((ref) => DateTime.now);
final biometriaProvider = Provider<Biometria>((ref) => BiometriaDoAparelho());
final infoDoAparelhoProvider = Provider<Future<InfoDoAparelho> Function()>((ref) => () async {
  final android = await DeviceInfoPlugin().androidInfo;
  final pacote = await PackageInfo.fromPlatform();
  return InfoDoAparelho(
    modelo: '${android.manufacturer} ${android.model}',
    sistema: 'Android ${android.version.release}',
    versaoApp: '${pacote.version}+${pacote.buildNumber}',
  );
});

final sessaoProvider = NotifierProvider<ControleDaSessao, EstadoSessao>(ControleDaSessao.new);

/// Liga a [Sessao] ao estado observado pelas telas.
class ControleDaSessao extends Notifier<EstadoSessao> {
  late Sessao sessao;

  /// Registrado pela fila quando ela existe (a fila observa a sessão; o contrário formaria um ciclo).
  Future<void> Function()? enviarFila;

  @override
  EstadoSessao build() {
    sessao = Sessao(
      configuracao: ref.watch(configuracaoProvider),
      cofre: ref.watch(cofreProvider),
      identidade: ref.watch(identidadeProvider),
      biometria: ref.watch(biometriaProvider),
      aoMudar: (novo) => state = novo,
    );
    sessao.cadastrarCelular = () => ref.read(apiCampoProvider).cadastrarCelular();
    // 10.9.6: a fila pendente vai antes de apagar, quando der; depois o servidor fica sabendo que o celular limpou.
    sessao.apagarDadosLocais = () async {
      try {
        await enviarFila?.call();
      } on Exception {
        // Sem como enviar: apaga assim mesmo (o servidor registra o celular como revogado).
      }
      await ref.read(armazemProvider).apagar();
      try {
        await ref.read(apiCampoProvider).confirmarApagado();
      } on Exception {
        // Fica para o administrador ver como não confirmado.
      }
    };
    Future.microtask(sessao.iniciar);
    return const Carregando();
  }
}

final apiCampoProvider = Provider<ApiCampo>((ref) {
  final cliente = ClienteApi(
    base: ref.watch(configuracaoProvider).api,
    credenciais: ref.watch(sessaoProvider.notifier).sessao,
  );
  return ApiCampo(cliente, ref.watch(infoDoAparelhoProvider));
});
