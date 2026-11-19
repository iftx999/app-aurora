# Aurora Campo

App Android das equipes de campo da Aurora (doc 10 do back-end, M6; ADR 0047): jornada, OS do dia na ordem da rota,
execução com fila local que funciona sem sinal, fotos e sincronização com `/api/v1/campo`.

## Ambiente

- Flutter 3.47.9 (estável) e Android SDK (plataforma 36, build-tools 36.0.0).
- Endereços na compilação, nunca no código:
  `--dart-define=AURORA_API=https://api.empresa --dart-define=AURORA_IDENTIDADE=https://login.empresa`.
  Sem eles, o padrão é o ambiente local visto do emulador (`http://10.0.2.2:8080` e `:8180`), com HTTP liberado só no
  build de desenvolvimento.
- Keycloak: cliente público `aurora-campo` (PKCE, `dev.aurora.campo:/oauthredirect`, escopo `offline_access`) no
  realm de cada empresa.

## Comandos

```
flutter analyze
flutter test
flutter build apk --debug
```

## Estrutura

- `lib/autenticacao`: login OIDC, cofre (Keystore), PIN (PBKDF2), biometria e as regras da sessão.
- `lib/dados/api`: cliente HTTP da API de campo (token, celular, Problem Details).
- `lib/dados/modelos`: pacote do dia, OS, equipes e jornada (com a aplicação das diferenças do pacote).
- `lib/dados/local`: banco SQLCipher do celular (chave no Keystore): último pacote e início de jornada sem sinal.
- `lib/dados/localizacao.dart`: GPS pelo `geolocator_android` (o pacote geral traz dependências MPL do Linux).
- `lib/jornada`: o dia no celular (iniciar com ou sem sinal, atualizar, encerrar).
- `lib/app`: tema da Aurora, dependências (Riverpod) e rotas (go_router).
- `lib/telas`: telas do protótipo (`docs/prototipo-app-campo` no back-end).

Licenças das dependências: todas MIT, BSD ou Apache 2.0 (verificadas no pub.dev antes de adicionar).
