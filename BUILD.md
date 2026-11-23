# Build e catálogo de patches do 3105

## Sincronização com o painel

A IPA busca o catálogo por `GET https://painel.proxysystem.org/api/mobile/catalog`. O cliente resolve `packageURL` e `iconURL` relativos no mesmo domínio, confere o tamanho anunciado em `packageSize` e valida o pacote pelo decoder local. Se a resposta incluir `checksumSha256`, o hash também é conferido. O endpoint não exige `PATCH_SYNC_TOKEN`, e o cliente não envia mais heartbeat pelo protocolo tRPC antigo.

O pacote amostrado do painel usa schema 9. A compatibilidade desse exemplar foi verificada: o conteúdo passou pela autenticação AES-GCM e o digest SHA-256 da regra conferiu. O app passa a aceitar schemas 1–3 e 9; continua criando pacotes novos no schema 3. Isso valida o exemplar consultado, não versões futuras ou pacotes com outros formatos.

A base legada em `RemotePatchConfiguration.baseURL` foi mantida separada para os serviços `api/app-config.json` e `api/app-update.json`. No domínio novo, esses caminhos respondem com a página HTML do SPA, não com os dados JSON esperados pelo app. A sincronização de patches usa exclusivamente `mobileCatalogURL`.

Como o catálogo amostrado é acessível sem autenticação, os pacotes publicados nele podem ser baixados por qualquer cliente que conheça a rota. Não publique ali conteúdo que precise permanecer privado.

## Resultado do build

O projeto precisava do runner macOS porque este ambiente não tem Xcode. A configuração de `ThreeOneOSFive.xcodeproj` foi restaurada a partir do commit `d5bd3ca`, cujo run histórico havia compilado com o scheme `3105` e produto `X.app`. O código atualizado foi compilado com sucesso no GitHub Actions, workflow `Build iOS app - X`, run `45087201107`, a partir do commit `448c96d`. O runner macOS 26 passou a validação da integração, compilou o Release, empacotou e enviou o artifact `x-ios-ipa`.

A IPA gerada contém `Payload/X.app`, identificador `com.apple.mobile.MobileHouseArrest`, versão `2.0` (build `22`) e mínimo iOS `16.0`. O arquivo ZIP passou pela verificação de integridade. O workflow desativa a assinatura e a IPA não contém a pasta `_CodeSignature`; portanto, ela não pode ser instalada diretamente em um iPhone sem assinatura e perfil de provisionamento compatíveis, que não estão configurados neste repositório.
