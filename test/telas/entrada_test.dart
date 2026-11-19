import 'dart:convert';

import 'package:aurora_campo/app/aurora_app.dart';
import 'package:aurora_campo/app/dependencias.dart';
import 'package:aurora_campo/autenticacao/biometria.dart';
import 'package:aurora_campo/autenticacao/cofre.dart';
import 'package:aurora_campo/autenticacao/provedor_identidade.dart';
import 'package:aurora_campo/dados/local/arquivos_de_foto.dart';
import 'package:aurora_campo/dados/local/armazem_do_dia.dart';
import 'package:aurora_campo/nucleo/configuracao.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../apoio.dart';

class IdentidadeFalsa implements ProvedorIdentidade {
  @override
  Future<Tokens> entrar(Uri emissor) async => Tokens(
    acesso: 'x.${base64Url.encode(utf8.encode('{"given_name":"Ana"}')).replaceAll('=', '')}.y',
    expiraEm: DateTime.now().add(const Duration(minutes: 5)),
    renovacao: 'r',
  );

  @override
  Future<Tokens> renovar(Uri emissor, String renovacao) => entrar(emissor);

  @override
  Future<void> sair(Uri emissor, String? idToken) async {}
}

class SemBiometria implements Biometria {
  @override
  Future<bool> autenticar(String motivo) async => false;

  @override
  Future<bool> disponivel() async => false;
}

Future<void> digitar(WidgetTester tester, String pin) async {
  for (final d in pin.split('')) {
    await tester.tap(find.bySemanticsLabel('Número $d'));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

void main() {
  Widget app(CofreEmMemoria cofre, ApiFalsa api) => ProviderScope(
    overrides: [
      configuracaoProvider.overrideWithValue(
        Configuracao(api: Uri.parse('http://api'), identidade: Uri.parse('http://kc')),
      ),
      cofreProvider.overrideWithValue(cofre),
      identidadeProvider.overrideWithValue(IdentidadeFalsa()),
      biometriaProvider.overrideWithValue(SemBiometria()),
      apiCampoProvider.overrideWithValue(api),
      armazemProvider.overrideWithValue(ArmazemEmMemoria()),
      arquivosDeFotoProvider.overrideWithValue(ArquivosEmMemoria()),
      localizacaoProvider.overrideWithValue(GpsFalso()),
      relogioProvider.overrideWithValue(() => agoraDosTestes),
    ],
    child: const AuroraApp(),
  );

  testWidgets('primeiro uso até o início, e o PIN na reabertura', (tester) async {
    final cofre = CofreEmMemoria();
    final api = ApiFalsa();
    await tester.pumpWidget(app(cofre, api));
    await tester.pumpAndSettle();

    expect(find.text('Código da empresa'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'aurora');
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    expect(find.text('Empresa: aurora'), findsOneWidget);
    await tester.tap(find.text('Entrar com a conta da empresa'));
    await tester.pumpAndSettle();
    expect(api.cadastros, 1);

    expect(find.textContaining('Olá, Ana. Crie um PIN'), findsOneWidget);
    await digitar(tester, '123456');
    expect(find.text('Não use números em sequência.'), findsOneWidget);
    await digitar(tester, '482913');
    expect(find.text('Digite o PIN de novo para confirmar.'), findsOneWidget);
    await digitar(tester, '482913');
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.text('Bom dia, Ana'), findsOneWidget);

    // Bloqueia: PIN errado avisa quantas tentativas restam; o certo abre.
    await tester.tap(find.byTooltip('Mais opções'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bloquear'));
    await tester.pumpAndSettle();
    expect(find.text('Olá, Ana. Digite o PIN para desbloquear.'), findsOneWidget);
    await digitar(tester, '000001');
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.text('PIN incorreto. Restam 4 tentativas.'), findsOneWidget);
    await digitar(tester, '482913');
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.text('Bom dia, Ana'), findsOneWidget);
  });

  testWidgets('celular revogado mostra o bloqueio', (tester) async {
    final cofre = CofreEmMemoria()..valores['empresa'] = 'aurora';
    await tester.pumpWidget(app(cofre, ApiFalsa(revogado: true)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Entrar com a conta da empresa'));
    await tester.pumpAndSettle();
    expect(find.text('Este celular foi bloqueado'), findsOneWidget);
    expect(cofre.valores.containsKey('tokens'), isFalse);
  });

  testWidgets('a tela do PIN passa nas diretrizes de acessibilidade', (tester) async {
    final semantica = tester.ensureSemantics();
    final cofre = CofreEmMemoria()..valores['empresa'] = 'aurora';
    await tester.pumpWidget(app(cofre, ApiFalsa()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Entrar com a conta da empresa'));
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    semantica.dispose();
  });
}
