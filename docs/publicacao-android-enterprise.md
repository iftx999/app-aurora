# Publicação interna pelo Android Enterprise

Como o Aurora Campo chega aos celulares da empresa (P10: aparelhos da empresa, não do funcionário). Decisão do cliente
em 20/11/2026: **Android Enterprise**. Complementa a ADR 0047 do back-end.

## 1. Modo do aparelho

**Totalmente gerenciado** (fully managed, aparelho da empresa). O perfil de trabalho serve a celular pessoal, que não
é o caso. O cadastro é feito pelo console do MDM (QR code, zero-touch ou Knox Mobile Enrollment).

## 2. Chave de assinatura (uma vez, pela empresa)

```
keytool -genkeypair -keystore aurora-campo.jks -alias aurora-campo -keyalg RSA -keysize 4096 -validity 10000 \
  -dname "CN=Aurora Campo, O=<empresa>, C=BR"
```

- O arquivo e as senhas ficam no cofre de segredos da empresa (e no do CI), **nunca no repositório**. O
  `.gitignore` já bloqueia `*.jks` e `*.keystore`.
- **Perder a chave significa não conseguir mais atualizar o app nos celulares.** Guarde duas cópias em lugares
  diferentes. No Managed Google Play, ative a assinatura de apps do Google Play: a chave acima vira só a de upload
  e, se ela vazar ou se perder, pode ser trocada.

## 3. Gerar o release

```
export AURORA_ASSINATURA_ARQUIVO=/caminho/aurora-campo.jks
export AURORA_ASSINATURA_SENHA=…            # senha do arquivo
export AURORA_ASSINATURA_ALIAS=aurora-campo
export AURORA_ASSINATURA_SENHA_CHAVE=…      # se for diferente da do arquivo
flutter build appbundle --release --build-name=1.0.0 --build-number=<n>
```

- `--build-number` precisa **subir a cada publicação** (é o `versionCode`; o Android recusa um número igual ou
  menor). Use o número do pipeline.
- Sem as variáveis, o build de release para com a explicação: o app nunca sai assinado com a chave de debug.
- O Managed Google Play aceita o `.aab`. Para um EMM que só aceita APK: `flutter build apk --release
  --split-per-abi` e envie o `app-arm64-v8a-release.apk` (o APK com todas as arquiteturas tem cerca de 75 MB).
- **Nome do pacote:** `dev.aurora.campo`. No Google Play ele é permanente depois da primeira publicação. Se a
  empresa quiser um nome do domínio dela (ex.: `br.com.empresa.aurora.campo`), a troca precisa ser feita **antes**
  (`applicationId` em `android/app/build.gradle.kts` e o esquema de retorno do login nos realms).

## 4. Publicar como app privado

No console do MDM: **Managed Google Play → Apps privados → enviar o `.aab`**, visível só para a organização. Na
política dos aparelhos das equipes, instale com **instalação forçada** (`FORCE_INSTALLED`), para o agente não
conseguir desinstalar, e **atualização automática de alta prioridade** (`AUTO_UPDATE_HIGH_PRIORITY`), para a
versão nova chegar sem esperar Wi-Fi ou carregador.

## 5. Configuração gerenciada (por empresa)

O mesmo app serve a todas as empresas: o console preenche os campos abaixo (`res/xml/app_restrictions.xml`) e o app
os lê ao abrir. Uma mudança no console vale na próxima abertura do app. Campo vazio ou inválido usa o valor da
compilação.

| Chave | Campo no console | Regra |
|---|---|---|
| `api_url` | Endereço da API da Aurora | HTTPS |
| `identidade_url` | Endereço do login (Keycloak) | HTTPS, sem `/realms` |
| `codigo_empresa` | Código da empresa | minúsculas, números e hífen. Fixa a empresa: o app não pergunta nem deixa trocar. Se o código mudar, os dados da empresa anterior são apagados do celular |
| `mapa_tiles` | Tiles do mapa | HTTPS com `{z}/{x}/{y}` (provedor contratado ou servidor próprio) |
| `mapa_atribuicao` | Atribuição do mapa | texto exigido pelo provedor |

## 6. Política recomendada para os aparelhos das equipes

Nomes da Android Management API entre parênteses; cada console tem o equivalente.

| Item | Valor | Por quê |
|---|---|---|
| Permissões do Aurora Campo (`permissionGrants`) | conceder localização precisa e aproximada, câmera e notificações | o agente não trava no primeiro uso. A localização só é coletada com a jornada aberta e com a notificação fixa à vista (RN-27, RIPD) |
| Localização em segundo plano | não conceder | o app não pede: a coleta usa serviço em primeiro plano |
| Data e hora automáticas (`autoDateAndTimeZone`) | obrigatórias | a hora dos eventos vem do celular (RN-26 marca relógio adiantado) |
| Bloqueio de tela (`passwordRequirements`) | obrigatório, PIN de 6 ou mais dígitos ou biometria | camada a mais além do PIN do app |
| Opções de desenvolvedor e depuração USB | desligadas | evita extrair dados do app |
| Fontes desconhecidas | bloqueadas | só apps da empresa |
| Otimização de bateria | Aurora Campo fora da lista, quando o console permitir (em Samsung, por OEMConfig/Knox) | alguns fabricantes encerram serviços em primeiro plano e a fila para de sair em segundo plano |
| Saída do MDM ou perda do aparelho | apagar o aparelho, e **também** revogar o celular na Aurora (tela Celulares) | a revogação na Aurora faz o app enviar a fila e apagar os dados mesmo se o aparelho voltar à rede antes do wipe |

## 7. Primeiro teste em aparelho (antes de liberar às equipes)

1. Cadastrar um aparelho de teste no MDM com a política acima e a configuração gerenciada da empresa de
   homologação.
2. Conferir: login sem a tela de empresa; PIN e biometria; iniciar jornada (GPS, notificação "Jornada em
   andamento", rota chegando em até 1 min e mapa com os tiles do provedor); iniciar, paralisar e encerrar uma OS
   com fotos **sem sinal** e depois com sinal; app em segundo plano por 30 min enviando posições; revogar o celular
   na Aurora e ver o app apagar os dados.
3. Atualizar o app (publicar versão com `--build-number` maior) e conferir que a fila e o banco migram sem perda.
