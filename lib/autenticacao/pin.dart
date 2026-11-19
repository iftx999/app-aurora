import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// PIN de desbloqueio (doc 10, 10.9.6): 6 dígitos, guardado só como PBKDF2-HMAC-SHA256 com sal aleatório. Depois de
/// [tentativas] erros seguidos o app apaga a sessão e exige login de novo.
class Pin {
  static const tamanho = 6;
  static const tentativas = 5;
  static const iteracoes = 120000;

  static final _apenasDigitos = RegExp(r'^\d{6}$');

  /// Recusa PIN fraco: sequência (123456, 654321) ou um dígito repetido.
  static String? problema(String pin) {
    if (!_apenasDigitos.hasMatch(pin)) {
      return 'O PIN tem 6 números.';
    }
    if (pin.split('').toSet().length == 1) {
      return 'Não use o mesmo número repetido.';
    }
    if ('0123456789'.contains(pin) || '9876543210'.contains(pin)) {
      return 'Não use números em sequência.';
    }
    return null;
  }

  static Uint8List novoSal() {
    final aleatorio = Random.secure();
    return Uint8List.fromList(List.generate(16, (_) => aleatorio.nextInt(256)));
  }

  static String resumo(String pin, List<int> sal, {int iteracoes = iteracoes}) =>
      base64Encode(pbkdf2(utf8.encode(pin), sal, iteracoes, 32));

  /// Comparação em tempo constante.
  static bool confere(String pin, List<int> sal, String resumoGuardado, {int iteracoes = iteracoes}) {
    final calculado = utf8.encode(resumo(pin, sal, iteracoes: iteracoes));
    final guardado = utf8.encode(resumoGuardado);
    if (calculado.length != guardado.length) {
      return false;
    }
    var diferenca = 0;
    for (var i = 0; i < calculado.length; i++) {
      diferenca |= calculado[i] ^ guardado[i];
    }
    return diferenca == 0;
  }

  /// PBKDF2 (RFC 8018) com HMAC-SHA256.
  static Uint8List pbkdf2(List<int> senha, List<int> sal, int iteracoes, int tamanhoChave) {
    final hmac = Hmac(sha256, senha);
    final blocos = (tamanhoChave / 32).ceil();
    final saida = BytesBuilder();
    for (var bloco = 1; bloco <= blocos; bloco++) {
      final inicial = Uint8List.fromList([...sal, bloco >> 24 & 0xff, bloco >> 16 & 0xff, bloco >> 8 & 0xff, bloco & 0xff]);
      var u = hmac.convert(inicial).bytes;
      final t = List<int>.from(u);
      for (var i = 1; i < iteracoes; i++) {
        u = hmac.convert(u).bytes;
        for (var j = 0; j < t.length; j++) {
          t[j] ^= u[j];
        }
      }
      saida.add(t);
    }
    return Uint8List.fromList(saida.toBytes().sublist(0, tamanhoChave));
  }
}
