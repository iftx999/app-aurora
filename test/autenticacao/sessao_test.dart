import 'dart:convert';

import 'package:aurora_campo/autenticacao/biometria.dart';
import 'package:aurora_campo/autenticacao/cofre.dart';
import 'package:aurora_campo/autenticacao/estado_sessao.dart';
import 'package:aurora_campo/autenticacao/provedor_identidade.dart';
import 'package:aurora_campo/autenticacao/sessao.dart';
import 'package:aurora_campo/dados/api/erros.dart';
import 'package:aurora_campo/nucleo/configuracao.dart';
import 'package:flutter_test/flutter_test.dart';

String tokenCom(Map<String, dynamic> afirmacoes) =>
    'x.${base64Url.encode(utf8.encode(jsonEncode(afirmacoes))).replaceAll('=', '')}.y';

class IdentidadeFalsa implements ProvedorIdentidade {
  IdentidadeFalsa(this.agora);

  final DateTime Function() agora;
  Uri? emissorUsado;
  int renovacoes = 0;
  bool semSinal = false;

  @override
  Future<Tokens> entrar(Uri emissor) async {
    emissorUsado = emissor;
    return Tokens(
      acesso: tokenCom({'given_name': 'Ana'}),
      expiraEm: agora().add(const Duration(minutes: 5)),
      renovacao: 'r1',
      idToken: 'id',
    );
  }

  @override
  Future<Tokens> renovar(Uri emissor, String renovacao) async {
    if (semSinal) {
      throw Exception('sem rede');
    }
    renovacoes++;
    return Tokens(acesso: tokenCom({'given_name': 'Ana', 'n': renovacoes}), expiraEm: agora().add(const Duration(minutes: 5)), renovacao: 'r2');
  }

  @override
  Future<void> sair(Uri emissor, String? idToken) async {}
}

class BiometriaFalsa implements Biometria {
  bool aceita = true;

  @override
  Future<bool> autenticar(String motivo) async => aceita;

  @override
  Future<bool> disponivel() async => true;
}

void main() {
  late DateTime agora;
  late CofreEmMemoria cofre;
  late IdentidadeFalsa identidade;
  late List<EstadoSessao> estados;

  Sessao nova() => Sessao(
    configuracao: Configuracao(api: Uri.parse('http://api'), identidade: Uri.parse('http://kc/')),
    cofre: cofre,
    identidade: identidade,
    biometria: BiometriaFalsa(),
    agora: () => agora,
    aoMudar: estados.add,
  );

  setUp(() {
    agora = DateTime(2026, 11, 19, 8);
    cofre = CofreEmMemoria();
    identidade = IdentidadeFalsa(() => agora);
    estados = [];
  });

  test('primeiro uso: empresa, login no realm dela, cadastro do celular e PIN', () async {
    final sessao = nova();
    var cadastrou = false;
    sessao.cadastrarCelular = () async => cadastrou = true;
    await sessao.iniciar();
    expect(sessao.estado, isA<SemEmpresa>());
    expect(() => sessao.informarEmpresa('Ab!'), throwsFormatException);
    await sessao.informarEmpresa(' Aurora ');
    expect((sessao.estado as SemLogin).codigoEmpresa, 'aurora');

    await sessao.entrar();
    expect(identidade.emissorUsado.toString(), 'http://kc/realms/aurora');
    expect(cadastrou, isTrue);
    expect((sessao.estado as CriarPin).nome, 'Ana');
    expect(() => sessao.criarPin('123456'), throwsFormatException);
    await sessao.criarPin('482913');
    expect(sessao.estado, isA<Desbloqueada>());
    expect(cofre.valores.containsValue('482913'), isFalse);

    // Reabrir o app pede o PIN.
    final reaberta = nova();
    await reaberta.iniciar();
    expect((reaberta.estado as Bloqueada).tentativasRestantes, 5);
    await reaberta.desbloquear('482913');
    expect(reaberta.estado, isA<Desbloqueada>());
  });

  test('cinco PINs errados apagam a sessão e o PIN', () async {
    final sessao = nova();
    await sessao.informarEmpresa('aurora');
    await sessao.entrar();
    await sessao.criarPin('482913');
    await sessao.bloquear();
    for (var i = 0; i < 4; i++) {
      await sessao.desbloquear('000001');
    }
    expect((sessao.estado as Bloqueada).tentativasRestantes, 1);
    expect((sessao.estado as Bloqueada).erro, 'PIN incorreto.');
    await sessao.desbloquear('000001');
    expect(sessao.estado, isA<SemLogin>());
    expect((sessao.estado as SemLogin).aviso, contains('PIN errado'));
    expect(cofre.valores[ChavesDoCofre.tokens], isNull);
    expect(cofre.valores[ChavesDoCofre.pinResumo], isNull);
  });

  test('sem contato com o Keycloak por mais de 7 dias exige login', () async {
    final sessao = nova();
    await sessao.informarEmpresa('aurora');
    await sessao.entrar();
    await sessao.criarPin('482913');
    agora = agora.add(const Duration(days: 7, minutes: 1));
    final depois = nova();
    await depois.iniciar();
    expect((depois.estado as SemLogin).aviso, contains('7 dias'));
  });

  test('renova o token quando vence e conta como contato; sem sinal é SemConexao', () async {
    final sessao = nova();
    await sessao.informarEmpresa('aurora');
    await sessao.entrar();
    final primeiro = await sessao.tokenDeAcesso();
    expect(await sessao.tokenDeAcesso(), primeiro);
    agora = agora.add(const Duration(minutes: 6));
    expect(await sessao.tokenDeAcesso(), isNot(primeiro));
    expect(identidade.renovacoes, 1);
    expect(cofre.valores[ChavesDoCofre.contatoIdentidade], agora.toIso8601String());
    agora = agora.add(const Duration(minutes: 6));
    identidade.semSinal = true;
    expect(sessao.tokenDeAcesso(), throwsA(isA<SemConexao>()));
  });

  test('celular revogado no cadastro apaga tudo menos o identificador', () async {
    final sessao = nova();
    var apagou = false;
    sessao.apagarDadosLocais = () async => apagou = true;
    final id = await sessao.dispositivoId();
    expect(await sessao.dispositivoId(), id);
    sessao.cadastrarCelular = () async => throw const ErroDaApi(403, 'bloqueado', codigo: 'DISPOSITIVO_REVOGADO');
    await sessao.informarEmpresa('aurora');
    await sessao.entrar();
    expect(sessao.estado, isA<Revogada>());
    expect(apagou, isTrue);
    expect(cofre.valores.keys, [ChavesDoCofre.dispositivo]);
  });

  test('biometria desbloqueia', () async {
    final sessao = nova();
    await sessao.informarEmpresa('aurora');
    await sessao.entrar();
    await sessao.criarPin('482913');
    await sessao.bloquear();
    expect((sessao.estado as Bloqueada).biometria, isTrue);
    await sessao.desbloquearComBiometria();
    expect(sessao.estado, isA<Desbloqueada>());
  });
}
