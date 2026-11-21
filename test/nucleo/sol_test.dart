import 'package:aurora_campo/nucleo/sol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no equador, no equinócio, o sol nasce perto das 6h e se põe perto das 18h (hora solar)', () {
    final sol = nascerEPorDoSol(DateTime.utc(2026, 3, 20), 0, 0)!;
    expect(sol.nascer.difference(DateTime.utc(2026, 3, 20, 6)).inMinutes.abs(), lessThan(15));
    expect(sol.por.difference(DateTime.utc(2026, 3, 20, 18)).inMinutes.abs(), lessThan(15));
  });

  test('Limeira: dia mais longo no verão que no inverno, nascer por volta das 5h30 em novembro (horário de Brasília)', () {
    final novembro = nascerEPorDoSol(DateTime.utc(2026, 11, 21), -22.56, -47.40)!;
    final junho = nascerEPorDoSol(DateTime.utc(2026, 6, 21), -22.56, -47.40)!;
    final duracaoNov = novembro.por.difference(novembro.nascer);
    final duracaoJun = junho.por.difference(junho.nascer);
    expect(duracaoNov, greaterThan(duracaoJun + const Duration(hours: 1)));
    // UTC−3: nascer entre 5h e 6h, pôr entre 18h30 e 19h30.
    final nascerLocal = novembro.nascer.subtract(const Duration(hours: 3));
    final porLocal = novembro.por.subtract(const Duration(hours: 3));
    expect(nascerLocal.hour, 5);
    expect(porLocal.hour * 60 + porLocal.minute, inInclusiveRange(18 * 60 + 30, 19 * 60 + 30));
  });

  test('noite pela posição e, sem posição, pelas 18h às 6h', () {
    // 21/11, 12h e 23h em Limeira (UTC−3 → 15h e 2h UTC).
    expect(eNoite(DateTime.utc(2026, 11, 21, 15), latitude: -22.56, longitude: -47.40), isFalse);
    expect(eNoite(DateTime.utc(2026, 11, 22, 2), latitude: -22.56, longitude: -47.40), isTrue);
    expect(eNoite(DateTime(2026, 11, 21, 12)), isFalse);
    expect(eNoite(DateTime(2026, 11, 21, 19)), isTrue);
    expect(eNoite(DateTime(2026, 11, 21, 5, 59)), isTrue);
  });

  test('regiões polares sem nascer ou pôr do sol', () {
    expect(nascerEPorDoSol(DateTime.utc(2026, 6, 21), 80, 0), isNull);
  });
}
