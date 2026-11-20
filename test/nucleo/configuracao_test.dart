import 'package:aurora_campo/nucleo/configuracao.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('configuração gerenciada (Android Enterprise)', () {
    test('sem MDM, valem os da compilação', () {
      final c = Configuracao.doAmbiente();
      expect(c.api, Uri.parse('http://10.0.2.2:8080'));
      expect(c.empresaGerenciada, isNull);
      expect(c.mapa.tiles, Configuracao.osm.tiles);
    });

    test('o MDM define endereços, empresa e mapa', () {
      final c = Configuracao.doAmbiente(
        gerenciada: {
          'api_url': ' https://api.aurora.exemplo.com.br ',
          'identidade_url': 'https://login.aurora.exemplo.com.br',
          'codigo_empresa': 'Saneamento-Sul',
          'mapa_tiles': 'https://tiles.exemplo.com.br/{z}/{x}/{y}.png',
          'mapa_atribuicao': '© Exemplo',
        },
      );
      expect(c.api, Uri.parse('https://api.aurora.exemplo.com.br'));
      expect(c.emissor('saneamento-sul'), Uri.parse('https://login.aurora.exemplo.com.br/realms/saneamento-sul'));
      expect(c.empresaGerenciada, 'saneamento-sul');
      expect(c.mapa.tiles, 'https://tiles.exemplo.com.br/{z}/{x}/{y}.png');
      expect(c.mapa.atribuicao, '© Exemplo');
      expect(c.permitirHttp, isFalse);
    });

    test('valores inválidos do MDM são ignorados', () {
      final c = Configuracao.doAmbiente(
        gerenciada: {
          'api_url': 'ftp://api',
          'identidade_url': 'não é endereço',
          'codigo_empresa': 'empresa com espaço',
          'mapa_tiles': 'http://tiles/{z}/{x}/{y}.png',
        },
      );
      expect(c.api, Uri.parse('http://10.0.2.2:8080'));
      expect(c.identidade, Uri.parse('http://10.0.2.2:8180'));
      expect(c.empresaGerenciada, isNull);
      expect(c.mapa.tiles, Configuracao.osm.tiles);
    });
  });
}
