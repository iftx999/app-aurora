/// Datas e horas como o app mostra (pt-BR, hora local do celular).
library;

const _dias = ['Segunda', 'Terça', 'Quarta', 'Quinta', 'Sexta', 'Sábado', 'Domingo'];
const _meses = [
  'janeiro',
  'fevereiro',
  'março',
  'abril',
  'maio',
  'junho',
  'julho',
  'agosto',
  'setembro',
  'outubro',
  'novembro',
  'dezembro',
];

String _doisDigitos(int n) => n.toString().padLeft(2, '0');

/// "Quarta, 18 de novembro".
String diaPorExtenso(DateTime d) => '${_dias[d.weekday - 1]}, ${d.day} de ${_meses[d.month - 1]}';

/// "18 nov".
String diaCurto(DateTime d) => '${d.day} ${_meses[d.month - 1].substring(0, 3)}';

/// "07:12".
String hora(DateTime d) {
  final l = d.toLocal();
  return '${_doisDigitos(l.hour)}:${_doisDigitos(l.minute)}';
}

/// "Bom dia", "Boa tarde" ou "Boa noite".
String saudacao(DateTime d) => d.hour < 12 ? 'Bom dia' : (d.hour < 18 ? 'Boa tarde' : 'Boa noite');

/// Prazo relativo a [agora]: "até 17:00" hoje, "amanhã", "até 21 nov", "venceu 14:00".
String prazo(DateTime prazo, DateTime agora) {
  final p = prazo.toLocal();
  final hoje = DateTime(agora.year, agora.month, agora.day);
  final dia = DateTime(p.year, p.month, p.day);
  final dias = dia.difference(hoje).inDays;
  if (p.isBefore(agora)) return dias == 0 ? 'venceu ${hora(p)}' : 'venceu ${diaCurto(p)}';
  if (dias == 0) return 'até ${hora(p)}';
  if (dias == 1) return 'amanhã';
  return 'até ${diaCurto(p)}';
}
