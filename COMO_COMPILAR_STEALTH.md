# Como compilar o Modo Fantasma (Stealth)

Arquivos já estão no repositório:
- `ThreeOneOSFive/helpers/Stealth.h`
- `ThreeOneOSFive/helpers/Stealth.m`
- `ThreeOneOSFive/views/SettingsView.swift` (botão já existe)
- `ThreeOneOSFive/ThreeOneOSFive-Bridging-Header.h` (já importa o Stealth)

## Passo a passo no Xcode

### 1. Abrir o projeto
- Abra o Xcode
- File → Open
- Selecione o arquivo `ThreeOneOSFive.xcodeproj`

### 2. Localizar a pasta helpers
No Project Navigator (lado esquerdo):
- Expanda `ThreeOneOSFive`
- Expanda a pasta `helpers`

### 3. Adicionar Stealth.m e Stealth.h no target
- Clique com o **botão direito** em cima da pasta `helpers`
- Escolha **Add Files to "ThreeOneOSFive"...**
- Na janela do Finder, vá até:
  `ThreeOneOSFive/helpers/`
- Segure **Command** e selecione:
  - `Stealth.h`
  - `Stealth.m`
- Embaixo da janela:
  - Marque **Copy items if needed** (se aparecer)
  - Em **Add to targets** marque o target principal (ThreeOneOSFive / 3105)
- Clique em **Add**

### 4. Confirmar que os arquivos entraram
Olhe de novo na pasta `helpers`. Tem que aparecer:
- Stealth.h
- Stealth.m

### 5. Confirmar Bridging Header
- Clique no ícone azul do projeto no topo
- Selecione o **target** (ThreeOneOSFive)
- Aba **Build Settings**
- Busque por: `bridging`
- Em **Objective-C Bridging Header** deve estar:
  `ThreeOneOSFive/ThreeOneOSFive-Bridging-Header.h`

Se estiver vazio, coloque exatamente esse caminho.

### 6. Compilar
- Pressione **Cmd + B**
- Ou Product → Build

## Erros comuns

**Undefined symbol: ST_fullStealthPass**
→ Stealth.m não foi adicionado no target. Repita o passo 3 e marque o target corretamente.

**Stealth.h file not found**
→ Bridging Header está errado ou vazio. Volte no passo 5.

## Depois de instalar
Abra o app → Settings → seção **STEALTH** → botão **Ativar Modo Fantasma**.

Pronto.
