import '../dados/modelos/dia.dart';

/// RN-22 no celular: as mesmas regras de `ValoresDoEncerramento` no servidor, para o agente corrigir antes de salvar
/// (sem sinal, uma recusa só chegaria horas depois). Valores: número, texto, opção, lista de opções, sim/não, data e
/// hora (DateTime) e, nas fotos, a lista de ids.
class Formulario {
  Formulario(this.parametros);

  static const maximoDeTexto = 500;

  final List<ParametroDoServico> parametros;

  /// Parâmetros que valem com os valores atuais (os condicionados só quando a condição bate), na ordem da versão.
  List<ParametroDoServico> visiveis(Map<String, Object?> valores) {
    final comparaveis = <String, String>{};
    final lista = <ParametroDoServico>[];
    for (final p in parametros) {
      if (p.condicaoChave != null && comparaveis[p.condicaoChave] != p.condicaoValor) continue;
      lista.add(p);
      final v = valores[p.chave];
      if ((p.tipo == 'SIM_NAO' || p.tipo == 'LISTA') && v != null) comparaveis[p.chave] = '$v';
    }
    return lista;
  }

  /// Chave → o que falta ou está errado; vazio quando dá para salvar.
  Map<String, String> erros(Map<String, Object?> valores) => {
    for (final p in visiveis(valores)) p.chave: ?_erro(p, valores[p.chave]),
  };

  /// O que vai no evento: só os visíveis e preenchidos, no formato da API.
  Map<String, dynamic> paraEnvio(Map<String, Object?> valores) => {
    for (final p in visiveis(valores))
      if (!_vazio(valores[p.chave])) p.chave: _paraJson(valores[p.chave]),
  };

  static bool _vazio(Object? v) => v == null || (v is String && v.trim().isEmpty) || (v is List && v.isEmpty);

  static Object? _paraJson(Object? v) => switch (v) {
    final DateTime d => d.toUtc().toIso8601String(),
    final String s => s.trim(),
    _ => v,
  };

  String? _erro(ParametroDoServico p, Object? v) {
    if (_vazio(v)) return p.obrigatorio ? 'Preencha "${p.rotulo}".' : null;
    final min = p.minimo, max = p.maximo;
    switch (p.tipo) {
      case 'INTEIRO' || 'DECIMAL':
        if (v is! num) return 'Informe um número.';
        if (p.tipo == 'INTEIRO' && v != v.truncate()) return 'Informe um número inteiro.';
        if ((min != null && v < min) || (max != null && v > max)) return 'Fora da faixa ${faixa(p)}.';
      case 'TEXTO':
        final t = (v as String).trim().length;
        final lo = min?.toInt() ?? 0, hi = max?.toInt() ?? maximoDeTexto;
        if (t < lo || t > hi) return 'De $lo a $hi caracteres.';
      case 'LISTA':
        if (!p.opcoes.contains(v)) return 'Escolha uma das opções.';
      case 'FOTO':
        final n = (v as List).length;
        final lo = min?.toInt() ?? 0;
        if (n < lo || (max != null && n > max)) {
          return max == null ? 'Tire ao menos $lo foto(s).' : 'De $lo a ${max.toInt()} fotos.';
        }
    }
    return null;
  }

  /// "de 0,5 a 100", "até 6", "a partir de 1".
  static String faixa(ParametroDoServico p) {
    String n(num x) => x.toString().replaceAll('.', ',');
    final min = p.minimo, max = p.maximo;
    if (min != null && max != null) return 'de ${n(min)} a ${n(max)}';
    if (max != null) return 'até ${n(max)}';
    if (min != null) return 'a partir de ${n(min)}';
    return '';
  }
}
