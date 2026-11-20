import 'dart:convert';
import 'dart:math';

import 'package:path/path.dart' as caminho;
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../autenticacao/cofre.dart';
import '../api/api_campo.dart';
import '../modelos/evento.dart';
import '../modelos/foto.dart';

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

/// O que o celular guarda para trabalhar sem sinal (10.9.2 e 10.9.3): o último pacote baixado, o início de jornada
/// ainda não enviado e a fila de eventos, que sobrevive a fechar o app, reiniciar ou acabar a bateria.
abstract interface class ArmazemDoDia {
  /// JSON do pacote completo e quando foi baixado.
  Future<({Map<String, dynamic> pacote, DateTime baixadoEm})?> lerPacote();
  Future<void> guardarPacote(Map<String, dynamic> pacote, DateTime baixadoEm);

  /// Fim da jornada: o pacote antigo sai do celular (10.9.6); a fila fica até ser enviada.
  Future<void> apagarPacote();

  /// Última rota publicada baixada (para o mapa sem sinal) e o ETag dela; apagada com o pacote.
  Future<({Map<String, dynamic> rota, String? etag})?> lerRota();
  Future<void> guardarRota(Map<String, dynamic>? rota, {String? etag});
  Future<InicioPendente?> lerInicioPendente();
  Future<void> guardarInicioPendente(InicioPendente? inicio);

  /// Guarda o evento no fim da fila (numa transação: ou entra inteiro, ou não entra).
  /// Com as [fotos] que o evento referencia, na mesma transação.
  Future<void> registrarEvento(EventoDeCampo evento, {List<FotoDaOs> fotos = const []});

  /// Na ordem em que foram registradas.
  Future<List<FotoDaOs>> fotos({bool soPendentes = false});
  Future<void> atualizarFoto(FotoDaOs foto);

  /// Fotos já resolvidas (enviadas ou recusadas) saem do banco; o arquivo é apagado por quem chama.
  Future<void> esquecerFoto(String id);

  /// Na ordem em que foram registrados; [soPendentes] = os que o servidor ainda não recebeu.
  Future<List<EventoNaFila>> eventos({bool soPendentes = false, int? limite});
  Future<void> marcarRespostas(List<RespostaDoEvento> respostas, DateTime em);

  /// Recusado no envio sem resposta por evento (dados que o servidor nem aceita ler).
  Future<void> marcarRecusado(String id, String mensagem, DateTime em);
  Future<void> contarTentativa(Iterable<String> ids);

  /// Maior sequência já usada no celular para a OS (0 se nenhuma).
  Future<int> ultimaSequencia(String osId);

  /// Tira da fila os já respondidos antes de [antesDe] (o histórico do dia fica para a tela da fila).
  Future<void> esquecerRespondidos(DateTime antesDe);

  /// Posição da jornada no fim da fila de posições (RN-27).
  Future<void> guardarPosicao(AmostraDePosicao amostra);

  /// As mais antigas primeiro, com a [PosicaoNaFila.ordem] para tirar da fila depois do envio.
  Future<List<PosicaoNaFila>> posicoes({int? limite});
  Future<int> contarPosicoes();

  /// Tira da fila as posições até [ordem] (inclusive): enviadas ou recusadas.
  Future<void> esquecerPosicoes(int ordem);

  /// Posições lidas antes de [antesDe] saem do celular mesmo sem envio (minimização, RIPD).
  Future<void> esquecerPosicoesAntigas(DateTime antesDe);

  /// Celular revogado ou troca de empresa: apaga o banco inteiro.
  Future<void> apagar();
}

/// Posição guardada no celular esperando envio.
class PosicaoNaFila {
  const PosicaoNaFila(this.ordem, this.amostra);

  final int ordem;
  final AmostraDePosicao amostra;
}

/// Banco SQLite criptografado com SQLCipher; a chave (256 bits aleatórios) fica só no Keystore, pelo [Cofre].
class ArmazemSqlCipher implements ArmazemDoDia {
  ArmazemSqlCipher(this._cofre);

  static const _arquivo = 'aurora_campo.db';
  static const _chaveDoBanco = 'chave_banco';

  final Cofre _cofre;
  Future<Database>? _banco;

  Future<Database> _abrir() => _banco ??= _abrirAgora();

  Future<Database> _abrirAgora() async {
    var chave = await _cofre.ler(_chaveDoBanco);
    final local = caminho.join(await getDatabasesPath(), _arquivo);
    if (chave == null) {
      // Chave nova: um banco antigo (de antes de apagar o cofre) não abriria com ela.
      await deleteDatabase(local);
      final aleatorio = Random.secure();
      chave = base64Encode(List.generate(32, (_) => aleatorio.nextInt(256)));
      await _cofre.escrever(_chaveDoBanco, chave);
    }
    return openDatabase(
      local,
      password: chave,
      version: 4,
      onCreate: (db, _) async {
        await db.execute(_valor);
        await db.execute(_evento);
        await db.execute(_anexo);
        await db.execute(_posicao);
      },
      onUpgrade: (db, de, _) async {
        if (de < 2) await db.execute(_evento);
        if (de < 3) await db.execute(_anexo);
        if (de < 4) await db.execute(_posicao);
      },
    );
  }

  static const _valor = 'CREATE TABLE valor (chave TEXT PRIMARY KEY, json TEXT NOT NULL)';

  // ordem: autoincremento = ordem de registro, que é a ordem de envio.
  static const _anexo = '''
    CREATE TABLE anexo (
      ordem INTEGER PRIMARY KEY AUTOINCREMENT,
      id TEXT NOT NULL UNIQUE,
      os_id TEXT NOT NULL,
      parametro TEXT NOT NULL,
      caminho TEXT NOT NULL,
      tipo_midia TEXT NOT NULL,
      tamanho INTEGER NOT NULL,
      sha256 TEXT NOT NULL,
      tirada_em TEXT NOT NULL,
      situacao TEXT NOT NULL DEFAULT 'pendente',
      recebido INTEGER NOT NULL DEFAULT 0,
      recusa TEXT
    )''';

  static const _posicao = '''
    CREATE TABLE posicao (
      ordem INTEGER PRIMARY KEY AUTOINCREMENT,
      momento TEXT NOT NULL,
      latitude REAL NOT NULL,
      longitude REAL NOT NULL,
      precisao_m REAL
    )''';

  static const _evento = '''
    CREATE TABLE evento (
      ordem INTEGER PRIMARY KEY AUTOINCREMENT,
      id TEXT NOT NULL UNIQUE,
      os_id TEXT NOT NULL,
      sequencia INTEGER NOT NULL,
      json TEXT NOT NULL,
      situacao TEXT NOT NULL DEFAULT 'pendente',
      mensagem TEXT,
      respondido_em TEXT,
      tentativas INTEGER NOT NULL DEFAULT 0,
      UNIQUE (os_id, sequencia)
    )''';

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
  Future<void> apagarPacote() => _escrever('pacote', null);

  @override
  Future<({Map<String, dynamic> rota, String? etag})?> lerRota() async {
    final v = await _ler('rota');
    return v == null ? null : (rota: v['rota'] as Map<String, dynamic>, etag: v['etag'] as String?);
  }

  @override
  Future<void> guardarRota(Map<String, dynamic>? rota, {String? etag}) =>
      _escrever('rota', rota == null ? null : {'rota': rota, 'etag': etag});

  @override
  Future<InicioPendente?> lerInicioPendente() async {
    final v = await _ler('inicio_pendente');
    return v == null ? null : InicioPendente.deJson(v);
  }

  @override
  Future<void> guardarInicioPendente(InicioPendente? inicio) => _escrever('inicio_pendente', inicio?.paraJson());

  @override
  Future<void> registrarEvento(EventoDeCampo evento, {List<FotoDaOs> fotos = const []}) async {
    final db = await _abrir();
    await db.transaction((t) async {
      await t.insert('evento', {
        'id': evento.id,
        'os_id': evento.osId,
        'sequencia': evento.sequencia,
        'json': jsonEncode(evento.paraJson()),
      });
      for (final f in fotos) {
        await t.insert('anexo', {
          'id': f.id,
          'os_id': f.osId,
          'parametro': f.parametro,
          'caminho': f.caminho,
          'tipo_midia': f.tipoMidia,
          'tamanho': f.tamanho,
          'sha256': f.sha256,
          'tirada_em': f.tiradaEm.toIso8601String(),
        });
      }
    });
  }

  @override
  Future<List<FotoDaOs>> fotos({bool soPendentes = false}) async {
    final linhas = await (await _abrir()).query(
      'anexo',
      where: soPendentes ? "situacao = 'pendente'" : null,
      orderBy: 'ordem',
    );
    return [
      for (final l in linhas)
        FotoDaOs(
          id: l['id'] as String,
          osId: l['os_id'] as String,
          parametro: l['parametro'] as String,
          caminho: l['caminho'] as String,
          tipoMidia: l['tipo_midia'] as String,
          tamanho: l['tamanho'] as int,
          sha256: l['sha256'] as String,
          tiradaEm: DateTime.parse(l['tirada_em'] as String),
          situacao: SituacaoDaFoto.values.byName(l['situacao'] as String),
          recebido: l['recebido'] as int,
          recusa: l['recusa'] as String?,
        ),
    ];
  }

  @override
  Future<void> atualizarFoto(FotoDaOs foto) async {
    await (await _abrir()).update(
      'anexo',
      {'situacao': foto.situacao.name, 'recebido': foto.recebido, 'recusa': foto.recusa},
      where: 'id = ?',
      whereArgs: [foto.id],
    );
  }

  @override
  Future<void> esquecerFoto(String id) async {
    await (await _abrir()).delete('anexo', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<List<EventoNaFila>> eventos({bool soPendentes = false, int? limite}) async {
    final linhas = await (await _abrir()).query(
      'evento',
      where: soPendentes ? "situacao = 'pendente'" : null,
      orderBy: 'ordem',
      limit: limite,
    );
    return [
      for (final l in linhas)
        EventoNaFila(
          EventoDeCampo.deJson(jsonDecode(l['json'] as String) as Map<String, dynamic>),
          situacao: SituacaoDoEnvio.values.byName(l['situacao'] as String),
          mensagem: l['mensagem'] as String?,
          respondidoEm: l['respondido_em'] == null ? null : DateTime.parse(l['respondido_em'] as String),
          tentativas: l['tentativas'] as int,
        ),
    ];
  }

  @override
  Future<void> marcarRespostas(List<RespostaDoEvento> respostas, DateTime em) async {
    final db = await _abrir();
    await db.transaction((t) async {
      for (final r in respostas) {
        await t.update(
          'evento',
          {'situacao': r.situacao.name, 'mensagem': r.mensagem, 'respondido_em': em.toIso8601String()},
          where: 'id = ?',
          whereArgs: [r.id],
        );
      }
    });
  }

  @override
  Future<void> marcarRecusado(String id, String mensagem, DateTime em) =>
      marcarRespostas([RespostaDoEvento(id: id, situacao: SituacaoDoEnvio.rejeitado, mensagem: mensagem)], em);

  @override
  Future<void> contarTentativa(Iterable<String> ids) async {
    final lista = ids.toList();
    if (lista.isEmpty) return;
    await (await _abrir()).rawUpdate(
      'UPDATE evento SET tentativas = tentativas + 1 WHERE id IN (${List.filled(lista.length, '?').join(',')})',
      lista,
    );
  }

  @override
  Future<int> ultimaSequencia(String osId) async {
    final r = await (await _abrir()).rawQuery('SELECT max(sequencia) AS s FROM evento WHERE os_id = ?', [osId]);
    return (r.first['s'] as int?) ?? 0;
  }

  @override
  Future<void> esquecerRespondidos(DateTime antesDe) async {
    await (await _abrir()).delete(
      'evento',
      where: "situacao <> 'pendente' AND respondido_em < ?",
      whereArgs: [antesDe.toIso8601String()],
    );
  }

  @override
  Future<void> guardarPosicao(AmostraDePosicao amostra) async {
    await (await _abrir()).insert('posicao', {
      'momento': amostra.momento.toUtc().toIso8601String(),
      'latitude': amostra.posicao.latitude,
      'longitude': amostra.posicao.longitude,
      'precisao_m': amostra.posicao.precisaoM,
    });
  }

  @override
  Future<List<PosicaoNaFila>> posicoes({int? limite}) async {
    final linhas = await (await _abrir()).query('posicao', orderBy: 'ordem', limit: limite);
    return [
      for (final l in linhas)
        PosicaoNaFila(
          l['ordem'] as int,
          AmostraDePosicao(
            DateTime.parse(l['momento'] as String),
            Posicao(
              (l['latitude'] as num).toDouble(),
              (l['longitude'] as num).toDouble(),
              precisaoM: (l['precisao_m'] as num?)?.toDouble(),
            ),
          ),
        ),
    ];
  }

  @override
  Future<int> contarPosicoes() async =>
      ((await (await _abrir()).rawQuery('SELECT count(*) AS n FROM posicao')).first['n'] as int?) ?? 0;

  @override
  Future<void> esquecerPosicoes(int ordem) async {
    await (await _abrir()).delete('posicao', where: 'ordem <= ?', whereArgs: [ordem]);
  }

  @override
  Future<void> esquecerPosicoesAntigas(DateTime antesDe) async {
    // ISO 8601 em UTC ordena como texto.
    await (await _abrir()).delete('posicao', where: 'momento < ?', whereArgs: [antesDe.toUtc().toIso8601String()]);
  }

  @override
  Future<void> apagar() async {
    final aberto = _banco;
    _banco = null;
    if (aberto != null) await (await aberto).close();
    await deleteDatabase(caminho.join(await getDatabasesPath(), _arquivo));
    await _cofre.apagar(_chaveDoBanco);
  }
}

/// Para testes; mesmas regras do banco (id e sequência por OS únicos).
class ArmazemEmMemoria implements ArmazemDoDia {
  ({Map<String, dynamic> pacote, DateTime baixadoEm})? pacote;
  InicioPendente? inicio;
  ({Map<String, dynamic> rota, String? etag})? rota;
  final List<EventoNaFila> fila = [];
  final List<FotoDaOs> anexos = [];
  final List<PosicaoNaFila> filaDePosicoes = [];
  var _ordemDaPosicao = 0;

  @override
  Future<({Map<String, dynamic> pacote, DateTime baixadoEm})?> lerPacote() async => pacote;

  @override
  Future<void> guardarPacote(Map<String, dynamic> pacote, DateTime baixadoEm) async =>
      this.pacote = (pacote: pacote, baixadoEm: baixadoEm);

  @override
  Future<void> apagarPacote() async => pacote = null;

  @override
  Future<({Map<String, dynamic> rota, String? etag})?> lerRota() async => rota;

  @override
  Future<void> guardarRota(Map<String, dynamic>? rota, {String? etag}) async =>
      this.rota = rota == null ? null : (rota: rota, etag: etag);

  @override
  Future<InicioPendente?> lerInicioPendente() async => inicio;

  @override
  Future<void> guardarInicioPendente(InicioPendente? inicio) async => this.inicio = inicio;

  @override
  Future<void> registrarEvento(EventoDeCampo evento, {List<FotoDaOs> fotos = const []}) async {
    if (fila.any(
      (e) => e.evento.id == evento.id || (e.evento.osId == evento.osId && e.evento.sequencia == evento.sequencia),
    )) {
      throw StateError('Evento ou sequência repetida.');
    }
    fila.add(EventoNaFila(evento));
    anexos.addAll(fotos);
  }

  @override
  Future<List<FotoDaOs>> fotos({bool soPendentes = false}) async =>
      anexos.where((f) => !soPendentes || f.situacao == SituacaoDaFoto.pendente).toList();

  @override
  Future<void> atualizarFoto(FotoDaOs foto) async {
    final i = anexos.indexWhere((f) => f.id == foto.id);
    if (i >= 0) anexos[i] = foto;
  }

  @override
  Future<void> esquecerFoto(String id) async => anexos.removeWhere((f) => f.id == id);

  @override
  Future<List<EventoNaFila>> eventos({bool soPendentes = false, int? limite}) async {
    final lista = fila.where((e) => !soPendentes || e.situacao == SituacaoDoEnvio.pendente);
    return (limite == null ? lista : lista.take(limite)).toList();
  }

  @override
  Future<void> marcarRespostas(List<RespostaDoEvento> respostas, DateTime em) async {
    for (final r in respostas) {
      final i = fila.indexWhere((e) => e.evento.id == r.id);
      if (i >= 0) {
        fila[i] = EventoNaFila(
          fila[i].evento,
          situacao: r.situacao,
          mensagem: r.mensagem,
          respondidoEm: em,
          tentativas: fila[i].tentativas,
        );
      }
    }
  }

  @override
  Future<void> marcarRecusado(String id, String mensagem, DateTime em) =>
      marcarRespostas([RespostaDoEvento(id: id, situacao: SituacaoDoEnvio.rejeitado, mensagem: mensagem)], em);

  @override
  Future<void> contarTentativa(Iterable<String> ids) async {
    for (var i = 0; i < fila.length; i++) {
      final e = fila[i];
      if (ids.contains(e.evento.id)) {
        fila[i] = EventoNaFila(e.evento, situacao: e.situacao, mensagem: e.mensagem, tentativas: e.tentativas + 1);
      }
    }
  }

  @override
  Future<int> ultimaSequencia(String osId) async =>
      fila.where((e) => e.evento.osId == osId).fold<int>(0, (m, e) => max(m, e.evento.sequencia));

  @override
  Future<void> esquecerRespondidos(DateTime antesDe) async =>
      fila.removeWhere((e) => e.situacao.recebido && (e.respondidoEm?.isBefore(antesDe) ?? false));

  @override
  Future<void> guardarPosicao(AmostraDePosicao amostra) async =>
      filaDePosicoes.add(PosicaoNaFila(++_ordemDaPosicao, amostra));

  @override
  Future<List<PosicaoNaFila>> posicoes({int? limite}) async =>
      (limite == null ? filaDePosicoes : filaDePosicoes.take(limite)).toList();

  @override
  Future<int> contarPosicoes() async => filaDePosicoes.length;

  @override
  Future<void> esquecerPosicoes(int ordem) async => filaDePosicoes.removeWhere((p) => p.ordem <= ordem);

  @override
  Future<void> esquecerPosicoesAntigas(DateTime antesDe) async =>
      filaDePosicoes.removeWhere((p) => p.amostra.momento.isBefore(antesDe));

  @override
  Future<void> apagar() async {
    pacote = null;
    inicio = null;
    rota = null;
    fila.clear();
    anexos.clear();
    filaDePosicoes.clear();
  }
}
