import 'dart:convert';
import 'dart:math';

import 'package:path/path.dart' as caminho;
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../autenticacao/cofre.dart';

/// Início de jornada feito sem sinal, enviado quando a conexão voltar.
class InicioPendente {
  const InicioPendente({required this.id, required this.equipeId, required this.ocorridoEm, required this.posicao});

  factory InicioPendente.deJson(Map<String, dynamic> j) => InicioPendente(
    id: j['id'] as String,
    equipeId: j['equipeId'] as String,
    ocorridoEm: DateTime.parse(j['ocorridoEm'] as String),
    posicao: j['posicao'] as Map<String, dynamic>,
  );

  final String id;
  final String equipeId;
  final DateTime ocorridoEm;
  final Map<String, dynamic> posicao;

  Map<String, Object?> paraJson() => {
    'id': id,
    'equipeId': equipeId,
    'ocorridoEm': ocorridoEm.toUtc().toIso8601String(),
    'posicao': posicao,
  };
}

/// O que o celular guarda do dia para trabalhar sem sinal (10.9.2): o último pacote baixado e o início de jornada
/// ainda não enviado. A fila de ações da execução entra no mesmo banco no M6c.
abstract interface class ArmazemDoDia {
  /// JSON do pacote completo e quando foi baixado.
  Future<({Map<String, dynamic> pacote, DateTime baixadoEm})?> lerPacote();
  Future<void> guardarPacote(Map<String, dynamic> pacote, DateTime baixadoEm);
  Future<InicioPendente?> lerInicioPendente();
  Future<void> guardarInicioPendente(InicioPendente? inicio);

  /// Celular revogado ou troca de empresa: apaga o banco inteiro.
  Future<void> apagar();
}

/// Banco SQLite criptografado com SQLCipher; a chave (256 bits aleatórios) fica só no Keystore, pelo [Cofre].
class ArmazemSqlCipher implements ArmazemDoDia {
  ArmazemSqlCipher(this._cofre);

  static const _arquivo = 'aurora_campo.db';
  static const _chaveDoBanco = 'chave_banco';

  final Cofre _cofre;
  Database? _banco;

  Future<Database> _abrir() async {
    final aberto = _banco;
    if (aberto != null) {
      return aberto;
    }
    var chave = await _cofre.ler(_chaveDoBanco);
    final local = caminho.join(await getDatabasesPath(), _arquivo);
    if (chave == null) {
      // Chave nova: um banco antigo (de antes de apagar o cofre) não abriria com ela.
      await deleteDatabase(local);
      final aleatorio = Random.secure();
      chave = base64Encode(List.generate(32, (_) => aleatorio.nextInt(256)));
      await _cofre.escrever(_chaveDoBanco, chave);
    }
    return _banco = await openDatabase(
      local,
      password: chave,
      version: 1,
      onCreate: (db, _) async {
        await db.execute('CREATE TABLE valor (chave TEXT PRIMARY KEY, json TEXT NOT NULL)');
      },
    );
  }

  Future<Map<String, dynamic>?> _ler(String chave) async {
    final linhas = await (await _abrir()).query('valor', where: 'chave = ?', whereArgs: [chave]);
    return linhas.isEmpty ? null : jsonDecode(linhas.first['json'] as String) as Map<String, dynamic>;
  }

  Future<void> _escrever(String chave, Map<String, Object?>? valor) async {
    final db = await _abrir();
    if (valor == null) {
      await db.delete('valor', where: 'chave = ?', whereArgs: [chave]);
    } else {
      await db.insert('valor', {
        'chave': chave,
        'json': jsonEncode(valor),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  @override
  Future<({Map<String, dynamic> pacote, DateTime baixadoEm})?> lerPacote() async {
    final v = await _ler('pacote');
    return v == null
        ? null
        : (pacote: v['pacote'] as Map<String, dynamic>, baixadoEm: DateTime.parse(v['baixadoEm'] as String));
  }

  @override
  Future<void> guardarPacote(Map<String, dynamic> pacote, DateTime baixadoEm) =>
      _escrever('pacote', {'pacote': pacote, 'baixadoEm': baixadoEm.toIso8601String()});

  @override
  Future<InicioPendente?> lerInicioPendente() async {
    final v = await _ler('inicio_pendente');
    return v == null ? null : InicioPendente.deJson(v);
  }

  @override
  Future<void> guardarInicioPendente(InicioPendente? inicio) => _escrever('inicio_pendente', inicio?.paraJson());

  @override
  Future<void> apagar() async {
    await _banco?.close();
    _banco = null;
    await deleteDatabase(caminho.join(await getDatabasesPath(), _arquivo));
    await _cofre.apagar(_chaveDoBanco);
  }
}

/// Para testes.
class ArmazemEmMemoria implements ArmazemDoDia {
  ({Map<String, dynamic> pacote, DateTime baixadoEm})? pacote;
  InicioPendente? inicio;

  @override
  Future<({Map<String, dynamic> pacote, DateTime baixadoEm})?> lerPacote() async => pacote;

  @override
  Future<void> guardarPacote(Map<String, dynamic> pacote, DateTime baixadoEm) async =>
      this.pacote = (pacote: pacote, baixadoEm: baixadoEm);

  @override
  Future<InicioPendente?> lerInicioPendente() async => inicio;

  @override
  Future<void> guardarInicioPendente(InicioPendente? inicio) async => this.inicio = inicio;

  @override
  Future<void> apagar() async {
    pacote = null;
    inicio = null;
  }
}
