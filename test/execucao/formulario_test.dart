import 'package:aurora_campo/dados/modelos/dia.dart';
import 'package:aurora_campo/execucao/formulario.dart';
import 'package:flutter_test/flutter_test.dart';

ParametroDoServico p(
  String chave,
  String tipo, {
  bool obrigatorio = true,
  num? min,
  num? max,
  List<String>? opcoes,
  String? se,
  String? igual,
}) => ParametroDoServico({
  'chave': chave,
  'rotulo': 'R $chave',
  'tipo': tipo,
  'obrigatorio': obrigatorio,
  'minimo': min,
  'maximo': max,
  'opcoes': opcoes ?? const [],
  'condicaoChave': se,
  'condicaoValor': igual,
});

void main() {
  // Como o parâmetro de ligação de esgoto do catálogo (doc 10, 10.5).
  final f = Formulario([
    p('viavel', 'SIM_NAO'),
    p('distancia', 'DECIMAL', min: 0.5, max: 100, se: 'viavel', igual: 'true'),
    p('motivo', 'TEXTO', min: 3, se: 'viavel', igual: 'false'),
    p('diametro', 'LISTA', opcoes: ['100', '150']),
    p('pecas', 'INTEIRO', obrigatorio: false),
    p('fotos', 'FOTO', min: 2, max: 3),
  ]);

  test('condição mostra só os parâmetros que valem', () {
    expect(f.visiveis({}).map((x) => x.chave), ['viavel', 'diametro', 'pecas', 'fotos']);
    expect(f.visiveis({'viavel': true}).map((x) => x.chave), contains('distancia'));
    expect(f.visiveis({'viavel': false}).map((x) => x.chave), allOf(contains('motivo'), isNot(contains('distancia'))));
  });

  test('erros como o servidor: obrigatório, faixa, inteiro, opção e quantidade de fotos', () {
    final erros = f.erros({
      'viavel': true,
      'distancia': 120,
      'diametro': '200',
      'pecas': 1.5,
      'fotos': ['a'],
    });
    expect(erros, {
      'distancia': 'Fora da faixa de 0,5 a 100.',
      'diametro': 'Escolha uma das opções.',
      'pecas': 'Informe um número inteiro.',
      'fotos': 'De 2 a 3 fotos.',
    });
    expect(f.erros({})['viavel'], 'Preencha "R viavel".');
    expect(f.erros({'viavel': false, 'motivo': ' a '})['motivo'], 'De 3 a 500 caracteres.');
  });

  test('envio leva só os visíveis e preenchidos', () {
    final valores = {
      'viavel': true,
      'distancia': 12.5,
      'motivo': 'escondido pela condição',
      'diametro': '100',
      'pecas': null,
      'fotos': ['a', 'b'],
    };
    expect(f.erros(valores), isEmpty);
    expect(f.paraEnvio(valores), {
      'viavel': true,
      'distancia': 12.5,
      'diametro': '100',
      'fotos': ['a', 'b'],
    });
  });

  test('data e hora vão em ISO 8601 com fuso', () {
    final g = Formulario([p('quando', 'DATA_HORA')]);
    expect(g.paraEnvio({'quando': DateTime.utc(2026, 11, 18, 14, 5)}), {'quando': '2026-11-18T14:05:00.000Z'});
  });
}
