# Build do 3105

Este repositório é uma cópia de trabalho independente do projeto original [YangJiiii/3105](https://github.com/YangJiiii/3105). A configuração de sincronização remota do app foi atualizada para o feed 3105 Remote Patches.

## Compilação e sincronização remota

O projeto exige macOS, Xcode e o SDK iOS. O workflow [Build iOS app](.github/workflows/build-ios.yml) compila o target `3105` em `Release` e publica o artefato `x-ios-ipa` no run do GitHub Actions por 14 dias.

Antes do build, configure em **Settings → Secrets and variables → Actions** o segredo de repositório chamado exatamente `PATCH_SYNC_TOKEN`, com o novo token de sincronização do backend. Atalho para a tela: [Actions secrets do repositório](https://github.com/bts2019amo-ctrl/3105-public-build-20260918-copy/settings/secrets/actions). Não use a senha do Gmail/Manus. O workflow escreve o valor somente em um `.xcconfig` temporário no runner e o expande no `Info.plist` da compilação; o token não fica no código-fonte. O workflow falha com uma mensagem clara se o segredo estiver ausente ou for curto demais.

O token é incorporado ao binário iOS porque o cliente precisa autenticar as chamadas ao feed; como qualquer credencial estática dentro de um app, ele pode ser extraído por engenharia reversa e não deve ser tratado como segredo impossível de obter. Se for exposto, deve ser rotacionado no backend e no GitHub Actions.

## Instalação

O workflow desativa a assinatura (`CODE_SIGNING_ALLOWED=NO`). Embora o artefato tenha extensão `.ipa`, ele é um pacote não assinado e não pode ser instalado em um iPhone sem assinatura/provisionamento compatível. Certificados, perfis de provisionamento e distribuição não estão configurados neste repositório.
