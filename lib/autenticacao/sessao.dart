import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../dados/api/cliente_api.dart';
import '../dados/api/erros.dart';
import '../nucleo/configuracao.dart';
import 'biometria.dart';
import 'cofre.dart';
import 'estado_sessao.dart';
import 'pin.dart';
import 'provedor_identidade.dart';

/// Chaves no cofre.
abstract final class ChavesDoCofre {
  static const empresa = 'empresa';
  static const tokens = 'tokens';
  static const contatoIdentidade = 'contato_identidade';
  static const pinResumo = 'pin_resumo';
  static const pinSal = 'pin_sal';
  static const tentativas = 'pin_tentativas';
  static const dispositivo = 'dispositivo';
  static const nome = 'nome';
}

/// Regras da entrada (doc 10, 10.9.6): login OIDC com sinal, PIN de 6 dígitos ou biometria para abrir, sessão sem
/// rede por até 7 dias desde o último contato com o Keycloak, 5 erros de PIN apagam a sessão, celular revogado apaga
/// tudo. Não conhece telas: quem desenha observa [estado].
class Sessao implements Credenciais {
  Sessao({
    required this.configuracao,
    required this.cofre,
    required this.identidade,
    required this.biometria,
    DateTime Function()? agora,
    this.aoMudar,
  }) : _agora = agora ?? DateTime.now;

  final Configuracao configuracao;
  final Cofre cofre;
  final ProvedorIdentidade identidade;
  final Biometria biometria;
  final DateTime Function() _agora;

  /// Chamado a cada mudança de estado.
  void Function(EstadoSessao)? aoMudar;

  /// Cadastro do celular na API depois do login; definido por quem monta o app.
  Future<void> Function()? cadastrarCelular;

  /// Apaga os dados locais (banco do dia, fila, fotos) quando o celular é revogado.
  Future<void> Function()? apagarDadosLocais;

  EstadoSessao _estado = const Carregando();
  EstadoSessao get estado => _estado;

  Tokens? _tokens;

  void _mudar(EstadoSessao novo) {
    _estado = novo;
    aoMudar?.call(novo);
  }

  Future<void> iniciar() async {
    final gerenciada = configuracao.empresaGerenciada;
    final guardada = await cofre.ler(ChavesDoCofre.empresa);
    if (gerenciada != null && gerenciada != guardada) {
      // O MDM fixou (ou mudou) a empresa: os dados da anterior saem do celular, como na troca manual.
      if (guardada != null) await _limparEmpresa();
      await cofre.escrever(ChavesDoCofre.empresa, gerenciada);
    }
    final empresa = await cofre.ler(ChavesDoCofre.empresa);
    if (empresa == null) {
      return _mudar(const SemEmpresa());
    }
    final tokens = await cofre.ler(ChavesDoCofre.tokens);
    if (tokens == null) {
      return _mudar(SemLogin(codigoEmpresa: empresa));
    }
    _tokens = Tokens.deJson(jsonDecode(tokens) as Map<String, dynamic>);
    if (await _expirada()) {
      await _esquecerSessao();
      return _mudar(SemLogin(
        codigoEmpresa: empresa,
        aviso: 'Faz mais de ${configuracao.semRedeMaxima.inDays} dias sem conexão. Entre de novo com sinal.',
      ));
    }
    if (await cofre.ler(ChavesDoCofre.pinResumo) == null) {
      return _mudar(CriarPin(nome: await _nome()));
    }
    await bloquear();
  }

  Future<void> informarEmpresa(String codigo) async {
    final limpo = codigo.trim().toLowerCase();
    if (!Configuracao.codigoDeEmpresaValido(limpo)) {
      throw const FormatException('Código da empresa inválido.');
    }
    await cofre.escrever(ChavesDoCofre.empresa, limpo);
    _mudar(SemLogin(codigoEmpresa: limpo));
  }

  /// Empresa fixada pelo MDM não se troca no celular.
  bool get empresaFixa => configuracao.empresaGerenciada != null;

  Future<void> trocarEmpresa() async {
    if (empresaFixa) return;
    await _limparEmpresa();
    await cofre.apagar(ChavesDoCofre.empresa);
    _mudar(const SemEmpresa());
  }

  Future<void> _limparEmpresa() async {
    await apagarDadosLocais?.call();
    await _esquecerSessao();
    await cofre.apagar(ChavesDoCofre.pinResumo);
    await cofre.apagar(ChavesDoCofre.pinSal);
  }

  /// Login no navegador do sistema e cadastro do celular. Falha de rede propaga para a tela avisar.
  Future<void> entrar() async {
    final empresa = await cofre.ler(ChavesDoCofre.empresa);
    if (empresa == null) {
      return _mudar(const SemEmpresa());
    }
    final tokens = await identidade.entrar(configuracao.emissor(empresa));
    await _guardar(tokens);
    await cofre.escrever(ChavesDoCofre.nome, tokens.nome);
    await cofre.escrever(ChavesDoCofre.tentativas, '0');
    try {
      await cadastrarCelular?.call();
    } on ErroDaApi catch (e) {
      if (e.celularRevogado) {
        return revogar();
      }
      rethrow;
    }
    if (await cofre.ler(ChavesDoCofre.pinResumo) == null) {
      _mudar(CriarPin(nome: tokens.nome));
    } else {
      _mudar(Desbloqueada(nome: tokens.nome));
    }
  }

  Future<void> criarPin(String pin) async {
    final problema = Pin.problema(pin);
    if (problema != null) {
      throw FormatException(problema);
    }
    final sal = Pin.novoSal();
    await cofre.escrever(ChavesDoCofre.pinSal, base64Encode(sal));
    await cofre.escrever(ChavesDoCofre.pinResumo, Pin.resumo(pin, sal));
    await cofre.escrever(ChavesDoCofre.tentativas, '0');
    _mudar(Desbloqueada(nome: await _nome()));
  }

  /// Volta a pedir o PIN (app em segundo plano por muito tempo, ou na abertura).
  Future<void> bloquear({String? erro}) async {
    final tentativas = int.tryParse(await cofre.ler(ChavesDoCofre.tentativas) ?? '0') ?? 0;
    _mudar(Bloqueada(
      nome: await _nome(),
      tentativasRestantes: Pin.tentativas - tentativas,
      biometria: await biometria.disponivel(),
      erro: erro,
    ));
  }

  Future<void> desbloquear(String pin) async {
    final resumo = await cofre.ler(ChavesDoCofre.pinResumo);
    final sal = await cofre.ler(ChavesDoCofre.pinSal);
    if (resumo == null || sal == null) {
      return _mudar(CriarPin(nome: await _nome()));
    }
    if (Pin.confere(pin, base64Decode(sal), resumo)) {
      await cofre.escrever(ChavesDoCofre.tentativas, '0');
      return _mudar(Desbloqueada(nome: await _nome()));
    }
    final erros = (int.tryParse(await cofre.ler(ChavesDoCofre.tentativas) ?? '0') ?? 0) + 1;
    if (erros >= Pin.tentativas) {
      await _esquecerSessao();
      await cofre.apagar(ChavesDoCofre.pinResumo);
      await cofre.apagar(ChavesDoCofre.pinSal);
      return _mudar(SemLogin(
        codigoEmpresa: await cofre.ler(ChavesDoCofre.empresa) ?? '',
        aviso: 'PIN errado ${Pin.tentativas} vezes. Entre de novo com a conta da empresa e crie outro PIN.',
      ));
    }
    await cofre.escrever(ChavesDoCofre.tentativas, '$erros');
    await bloquear(erro: 'PIN incorreto.');
  }

  Future<void> desbloquearComBiometria() async {
    if (await biometria.autenticar('Desbloquear o Aurora Campo')) {
      await cofre.escrever(ChavesDoCofre.tentativas, '0');
      _mudar(Desbloqueada(nome: await _nome()));
    }
  }

  /// Sai: encerra a sessão no Keycloak (se houver sinal) e apaga tokens e PIN; mantém a empresa.
  Future<void> sair() async {
    final empresa = await cofre.ler(ChavesDoCofre.empresa);
    try {
      if (empresa != null) {
        await identidade.sair(configuracao.emissor(empresa), _tokens?.idToken);
      }
    } on Exception {
      // Sem sinal: a sessão do Keycloak expira sozinha.
    }
    await _esquecerSessao();
    await cofre.apagar(ChavesDoCofre.pinResumo);
    await cofre.apagar(ChavesDoCofre.pinSal);
    _mudar(SemLogin(codigoEmpresa: empresa ?? ''));
  }

  /// Celular bloqueado (J13): apaga tudo, menos o identificador do celular (o servidor precisa reconhecê-lo).
  Future<void> revogar() async {
    final dispositivo = await cofre.ler(ChavesDoCofre.dispositivo);
    await apagarDadosLocais?.call();
    await cofre.apagarTudo();
    if (dispositivo != null) {
      await cofre.escrever(ChavesDoCofre.dispositivo, dispositivo);
    }
    _tokens = null;
    _mudar(const Revogada());
  }

  // ----- Credenciais para a API -----

  @override
  Future<String> dispositivoId() async {
    final atual = await cofre.ler(ChavesDoCofre.dispositivo);
    if (atual != null) {
      return atual;
    }
    final novo = const Uuid().v4();
    await cofre.escrever(ChavesDoCofre.dispositivo, novo);
    return novo;
  }

  /// Token válido; renova pelo Keycloak quando falta menos de 30 s. Sem sinal, [SemConexao].
  @override
  Future<String> tokenDeAcesso() async {
    final tokens = _tokens;
    if (tokens == null) {
      throw StateError('Sem sessão.');
    }
    if (tokens.expiraEm.isAfter(_agora().add(const Duration(seconds: 30)))) {
      return tokens.acesso;
    }
    final renovacao = tokens.renovacao;
    final empresa = await cofre.ler(ChavesDoCofre.empresa);
    if (renovacao == null || empresa == null) {
      throw StateError('Sessão sem renovação.');
    }
    try {
      final novos = await identidade.renovar(configuracao.emissor(empresa), renovacao);
      await _guardar(novos);
      return novos.acesso;
    } on Exception catch (e) {
      throw SemConexao(e);
    }
  }

  Future<void> _guardar(Tokens tokens) async {
    _tokens = tokens;
    await cofre.escrever(ChavesDoCofre.tokens, jsonEncode(tokens.paraJson()));
    await cofre.escrever(ChavesDoCofre.contatoIdentidade, _agora().toIso8601String());
  }

  Future<bool> _expirada() async {
    final contato = DateTime.tryParse(await cofre.ler(ChavesDoCofre.contatoIdentidade) ?? '');
    return contato == null || _agora().difference(contato) > configuracao.semRedeMaxima;
  }

  Future<void> _esquecerSessao() async {
    _tokens = null;
    await cofre.apagar(ChavesDoCofre.tokens);
    await cofre.apagar(ChavesDoCofre.contatoIdentidade);
    await cofre.apagar(ChavesDoCofre.tentativas);
  }

  Future<String> _nome() async => await cofre.ler(ChavesDoCofre.nome) ?? '';
}
