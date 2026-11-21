import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as caminho;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'cifra_de_fotos.dart';

/// Foto já reduzida, guardada no celular e ainda não ligada a um encerramento.
class FotoGuardada {
  const FotoGuardada({
    required this.id,
    required this.caminho,
    required this.tamanho,
    required this.sha256,
    required this.tiradaEm,
    this.tipoMidia = 'image/jpeg',
  });

  final String id;
  final String caminho;
  final int tamanho;
  final String sha256;
  final DateTime tiradaEm;
  final String tipoMidia;
}

/// Arquivos das fotos, na pasta privada do app (fora da galeria e do backup, que está desligado), criptografados à
/// parte (ADR 0051).
abstract interface class ArquivosDeFoto {
  /// Copia a foto da câmera para a pasta do app e calcula o resumo.
  Future<FotoGuardada> guardar(String origem, DateTime tiradaEm);

  /// Bytes da foto (decifrada) de [inicio] (inclusivo) a [fim] (exclusivo).
  Future<Uint8List> ler(String arquivo, int inicio, int fim);

  /// A foto inteira, decifrada (miniatura na tela).
  Future<Uint8List> lerTudo(String arquivo);
  Future<void> apagar(String arquivo);

  /// Celular revogado ou troca de empresa.
  Future<void> apagarTudo();
}

class ArquivosNoAparelho implements ArquivosDeFoto {
  ArquivosNoAparelho(this._cifra, {Future<Directory> Function()? base})
    : _base = base ?? getApplicationSupportDirectory;

  final CifraDeFotos _cifra;
  final Future<Directory> Function() _base;

  /// A última foto decifrada: o envio em partes lê a mesma foto várias vezes seguidas.
  ({String arquivo, Uint8List bytes})? _ultima;

  /// Fotos guardadas antes da ADR 0051 ficaram sem a extensão e continuam legíveis até serem enviadas.
  static const extensaoCifrada = '.jpg.cifrada';

  Future<Directory> _pasta() async {
    final pasta = Directory(caminho.join((await _base()).path, 'fotos'));
    if (!await pasta.exists()) await pasta.create(recursive: true);
    return pasta;
  }

  @override
  Future<FotoGuardada> guardar(String origem, DateTime tiradaEm) async {
    final id = const Uuid().v4();
    final claro = await File(origem).readAsBytes();
    final destino = caminho.join((await _pasta()).path, '$id$extensaoCifrada');
    await File(destino).writeAsBytes(await _cifra.cifrar(claro), flush: true);
    try {
      await File(origem).delete();
    } on FileSystemException {
      // O cache da câmera some sozinho.
    }
    // Tamanho e resumo da foto (o servidor confere a foto, não o arquivo cifrado).
    return FotoGuardada(
      id: id,
      caminho: destino,
      tamanho: claro.length,
      sha256: sha256.convert(claro).toString(),
      tiradaEm: tiradaEm,
    );
  }

  @override
  Future<Uint8List> lerTudo(String arquivo) async {
    final ultima = _ultima;
    if (ultima != null && ultima.arquivo == arquivo) return ultima.bytes;
    final bytes = await File(arquivo).readAsBytes();
    final claro = arquivo.endsWith(extensaoCifrada) ? await _cifra.decifrar(bytes) : bytes;
    _ultima = (arquivo: arquivo, bytes: claro);
    return claro;
  }

  @override
  Future<Uint8List> ler(String arquivo, int inicio, int fim) async =>
      Uint8List.sublistView(await lerTudo(arquivo), inicio, fim);

  @override
  Future<void> apagar(String arquivo) async {
    if (_ultima?.arquivo == arquivo) _ultima = null;
    final f = File(arquivo);
    if (await f.exists()) await f.delete();
  }

  @override
  Future<void> apagarTudo() async {
    _ultima = null;
    final pasta = await _pasta();
    if (await pasta.exists()) await pasta.delete(recursive: true);
    await _cifra.apagarChave();
  }
}

/// Para testes.
class ArquivosEmMemoria implements ArquivosDeFoto {
  final Map<String, Uint8List> arquivos = {};

  /// Bytes que [guardar] grava (a "foto" da câmera falsa).
  Uint8List conteudo = Uint8List.fromList(List.generate(2500, (i) => i % 256));

  @override
  Future<FotoGuardada> guardar(String origem, DateTime tiradaEm) async {
    final id = const Uuid().v4();
    final nome = '/fotos/$id.jpg';
    arquivos[nome] = conteudo;
    return FotoGuardada(
      id: id,
      caminho: nome,
      tamanho: conteudo.length,
      sha256: sha256.convert(conteudo).toString(),
      tiradaEm: tiradaEm,
    );
  }

  @override
  Future<Uint8List> ler(String arquivo, int inicio, int fim) async =>
      Uint8List.sublistView(arquivos[arquivo]!, inicio, fim);

  @override
  Future<Uint8List> lerTudo(String arquivo) async => arquivos[arquivo]!;

  @override
  Future<void> apagar(String arquivo) async => arquivos.remove(arquivo);

  @override
  Future<void> apagarTudo() async => arquivos.clear();
}
