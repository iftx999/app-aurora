import 'dart:math' as math;

/// Nascer e pôr do sol (algoritmo da NOAA, precisão de poucos minutos), para o modo noturno automático.
/// Devolve os instantes em UTC; nulo quando o sol não nasce ou não se põe no dia (regiões polares).
({DateTime nascer, DateTime por})? nascerEPorDoSol(DateTime dia, double latitude, double longitude) {
  final data = DateTime.utc(dia.year, dia.month, dia.day);
  final diaDoAno = data.difference(DateTime.utc(data.year)).inDays + 1;
  final gama = 2 * math.pi / 365 * (diaDoAno - 1);
  // Equação do tempo (minutos) e declinação (radianos).
  final eqTempo =
      229.18 *
      (0.000075 +
          0.001868 * math.cos(gama) -
          0.032077 * math.sin(gama) -
          0.014615 * math.cos(2 * gama) -
          0.040849 * math.sin(2 * gama));
  final declinacao =
      0.006918 -
      0.399912 * math.cos(gama) +
      0.070257 * math.sin(gama) -
      0.006758 * math.cos(2 * gama) +
      0.000907 * math.sin(2 * gama) -
      0.002697 * math.cos(3 * gama) +
      0.00148 * math.sin(3 * gama);
  final lat = latitude * math.pi / 180;
  // Zênite de 90,833°: refração e o raio do disco solar.
  final cosH =
      math.cos(90.833 * math.pi / 180) / (math.cos(lat) * math.cos(declinacao)) - math.tan(lat) * math.tan(declinacao);
  if (cosH < -1 || cosH > 1) return null;
  final h = math.acos(cosH) * 180 / math.pi;
  final nascerMin = 720 - 4 * (longitude + h) - eqTempo;
  final porMin = 720 - 4 * (longitude - h) - eqTempo;
  return (
    nascer: data.add(Duration(seconds: (nascerMin * 60).round())),
    por: data.add(Duration(seconds: (porMin * 60).round())),
  );
}

/// Noite no lugar: antes do nascer ou depois do pôr do sol. Sem lugar conhecido, das 18h às 6h no relógio do celular.
bool eNoite(DateTime agora, {double? latitude, double? longitude}) {
  if (latitude != null && longitude != null) {
    final sol = nascerEPorDoSol(agora.toUtc(), latitude, longitude);
    if (sol != null) {
      final t = agora.toUtc();
      return t.isBefore(sol.nascer) || !t.isBefore(sol.por);
    }
  }
  final local = agora.toLocal();
  return local.hour >= 18 || local.hour < 6;
}
