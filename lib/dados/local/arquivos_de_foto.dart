import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as caminho;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

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

/// Arquivos das fotos, na pasta privada do app (fora da galeria e do backup, que está desligado).
abstract interface class ArquivosDeFoto {
  /// Copia a foto da câmera para a pasta do app e calcula o resumo.
  Future<FotoGuardada> guardar(String origem, DateTime tiradaEm);

  /// Bytes de [inicio] (inclusivo) a [fim] (exclusivo).
  Future<Uint8List> ler(String arquivo, int inicio, int fim);
  Future<void> apagar(String arquivo);

  /// Celular revogado ou troca de empresa.
  Future<void> apagarTudo();
}

class ArquivosNoAparelho implements ArquivosDeFoto {
  Future<Directory> _pasta() async {
    final pasta = Directory(caminho.join((await getApplicationSupportDirectory()).path, 'fotos'));
    if (!await pasta.exists()) await pasta.create(recursive: true);
    return pasta;
  }

  @override
  Future<FotoGuardada> guardar(String origem, DateTime tiradaEm) async {
    final id = const Uuid().v4();
    final destino = caminho.join((await _pasta()).path, '$id.jpg');
    final arquivo = await File(origem).copy(destino);
    try {
      await File(origem).delete();
    } on FileSystemException {
      // O cache da câmera some sozinho.
    }
    final bytes = await arquivo.readAsBytes();
    return FotoGuardada(
      id: id,
      caminho: destino,
      tamanho: bytes.length,
      sha256: sha256.convert(bytes).toString(),
      tiradaEm: tiradaEm,
    );
  }

  @override
  Future<Uint8List> ler(String arquivo, int inicio, int fim) async {
    final f = await File(arquivo).open();
    try {
      await f.setPosition(inicio);
      return await f.read(fim - inicio);
    } finally {
      await f.close();
    }
  }

  @override
  Future<void> apagar(String arquivo) async {
    final f = File(arquivo);
    if (await f.exists()) await f.delete();
  }

  @override
  Future<void> apagarTudo() async {
    final pasta = await _pasta();
    if (await pasta.exists()) await pasta.delete(recursive: true);
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
  Future<void> apagar(String arquivo) async => arquivos.remove(arquivo);

  @override
  Future<void> apagarTudo() async => arquivos.clear();
}
