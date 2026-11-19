import 'dart:convert';

import 'package:aurora_campo/autenticacao/pin.dart';
import 'package:flutter_test/flutter_test.dart';

String hex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

void main() {
  test('PBKDF2-HMAC-SHA256 confere com os vetores conhecidos', () {
    expect(hex(Pin.pbkdf2(utf8.encode('password'), utf8.encode('salt'), 1, 32)),
        '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b');
    expect(hex(Pin.pbkdf2(utf8.encode('password'), utf8.encode('salt'), 2, 32)),
        'ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43');
  });

  test('recusa PIN fraco ou incompleto', () {
    expect(Pin.problema('12345'), isNotNull);
    expect(Pin.problema('111111'), isNotNull);
    expect(Pin.problema('123456'), isNotNull);
    expect(Pin.problema('654321'), isNotNull);
    expect(Pin.problema('12a456'), isNotNull);
    expect(Pin.problema('482913'), isNull);
  });

  test('o resumo confere só com o mesmo PIN e sal', () {
    final sal = Pin.novoSal();
    final resumo = Pin.resumo('482913', sal, iteracoes: 10);
    expect(Pin.confere('482913', sal, resumo, iteracoes: 10), isTrue);
    expect(Pin.confere('482914', sal, resumo, iteracoes: 10), isFalse);
    expect(Pin.confere('482913', Pin.novoSal(), resumo, iteracoes: 10), isFalse);
  });
}
