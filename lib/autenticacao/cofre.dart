import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Guarda segredos do app (tokens, PIN, chave do banco local) no Keystore do Android.
abstract interface class Cofre {
  Future<String?> ler(String chave);
  Future<void> escrever(String chave, String valor);
  Future<void> apagar(String chave);
  Future<void> apagarTudo();
}

class CofreSeguro implements Cofre {
  CofreSeguro() : _armazenamento = const FlutterSecureStorage();

  final FlutterSecureStorage _armazenamento;

  @override
  Future<String?> ler(String chave) => _armazenamento.read(key: chave);

  @override
  Future<void> escrever(String chave, String valor) => _armazenamento.write(key: chave, value: valor);

  @override
  Future<void> apagar(String chave) => _armazenamento.delete(key: chave);

  @override
  Future<void> apagarTudo() => _armazenamento.deleteAll();
}

/// Para testes.
class CofreEmMemoria implements Cofre {
  final Map<String, String> valores = {};

  @override
  Future<String?> ler(String chave) async => valores[chave];

  @override
  Future<void> escrever(String chave, String valor) async => valores[chave] = valor;

  @override
  Future<void> apagar(String chave) async => valores.remove(chave);

  @override
  Future<void> apagarTudo() async => valores.clear();
}
