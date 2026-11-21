import 'dart:io';
import 'dart:typed_data';

import 'package:aurora_campo/dados/local/arquivos_de_foto.dart';
import 'package:aurora_campo/dados/local/cifra_de_fotos.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

/// Cifra de teste (inverte os bits e põe 12 bytes na frente): o que importa é o arquivo não ter a foto em claro.
class CifraFalsa implements CifraDeFotos {
  int apagamentos = 0;

  @override
  Future<Uint8List> cifrar(Uint8List claro) async =>
      Uint8List.fromList([...List.filled(12, 7), for (final b in claro) b ^ 0xFF]);

  @override
  Future<Uint8List> decifrar(Uint8List cifrado) async =>
      Uint8List.fromList([for (final b in cifrado.sublist(12)) b ^ 0xFF]);

  @override
  Future<void> apagarChave() async => apagamentos++;
}

/// ADR 0051: fotos criptografadas à parte no celular.
void main() {
  late Directory base;
  late CifraFalsa cifra;
  late ArquivosNoAparelho arquivos;
  final foto = Uint8List.fromList(List.generate(3000, (i) => (i * 7) % 256));

  setUp(() async {
    base = await Directory.systemTemp.createTemp('aurora-fotos');
    cifra = CifraFalsa();
    arquivos = ArquivosNoAparelho(cifra, base: () async => base);
  });

  tearDown(() async {
    if (await base.exists()) await base.delete(recursive: true);
  });

  test('guarda cifrada, com tamanho e resumo da foto; o envio lê as partes em claro', () async {
    final origem = File('${base.path}/camera.jpg')..writeAsBytesSync(foto);
    final guardada = await arquivos.guardar(origem.path, DateTime(2026, 11, 21, 9));

    expect(origem.existsSync(), isFalse);
    expect(guardada.caminho, endsWith(ArquivosNoAparelho.extensaoCifrada));
    expect(guardada.tamanho, foto.length);
    expect(guardada.sha256, sha256.convert(foto).toString());
    final noDisco = File(guardada.caminho).readAsBytesSync();
    expect(noDisco, isNot(containsAllInOrder(foto.sublist(0, 64))));

    expect(await arquivos.ler(guardada.caminho, 0, 1000), foto.sublist(0, 1000));
    expect(await arquivos.ler(guardada.caminho, 1000, 3000), foto.sublist(1000));
    expect(await arquivos.lerTudo(guardada.caminho), foto);
  });

  test('foto guardada antes da criptografia continua legível', () async {
    final antiga = File('${base.path}/antiga.jpg')..writeAsBytesSync(foto);
    expect(await arquivos.ler(antiga.path, 10, 20), foto.sublist(10, 20));
  });

  test('revogação apaga as fotos e a chave', () async {
    final origem = File('${base.path}/camera.jpg')..writeAsBytesSync(foto);
    final guardada = await arquivos.guardar(origem.path, DateTime(2026, 11, 21, 9));
    await arquivos.apagarTudo();
    expect(File(guardada.caminho).existsSync(), isFalse);
    expect(cifra.apagamentos, 1);
  });
}
