# BlackGold Commander V2

Agente próprio do Ecossistema BlackGold para execução controlada no Windows, sem dependência operacional do Desktop Commander.

## Objetivo

O BlackGold Commander recebe jobs estruturados de um repositório privado de controle no GitHub, executa somente operações permitidas e grava o resultado de volta no mesmo repositório.

O agente é **pull-based**. Ele não depende do GitHub Actions self-hosted runner estar online para buscar trabalho.

## Princípios

- nenhum shell arbitrário remoto;
- caminhos de projeto restritos a `E:\`;
- nenhuma janela visível de CMD;
- fila e resultados em repositório privado;
- token GitHub armazenado localmente protegido por DPAPI do usuário do Windows;
- logs locais;
- instalação por tarefa agendada oculta no logon;
- GitHub Runner atual permanece como fallback;
- Desktop Commander não é requisito.

## Fluxo

1. `Install-BlackGoldCommander.ps1` obtém uma credencial GitHub já autenticada ou `BLACKGOLD_GITHUB_TOKEN`.
2. Descobre o repositório privado que contém `BLACKGOLD_COMMANDER_CONTROL.json`.
3. Protege o token com DPAPI e grava o estado local em `%LOCALAPPDATA%\BlackGold\Commander`.
4. Registra `BlackGold-Commander` no Agendador de Tarefas.
5. `BlackGold.Commander.ps1` consulta a fila privada, executa jobs seguros e publica os resultados.

## Capacidades V2

Filesystem: listar, ler texto, escrever texto e criar diretórios dentro de `E:\`.

Projetos: status Git, pull fast-forward e tarefas Gradle autorizadas.

Android: listar devices, iniciar AVD, instalar APK, abrir pacote e coletar logcat.

## Segurança

A fila não aceita PowerShell, CMD, Bash, Base64 script, command strings livres nem executáveis arbitrários.

A etapa seguinte, depois da validação desta branch, é integrar o Commander ao `CURRENT_TRUTH.json` e promover para `control-plane-stable`.
