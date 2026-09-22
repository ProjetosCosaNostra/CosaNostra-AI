# BlackGold GitHub Runner

Canal oficial de execução local via GitHub para o Ecossistema BlackGold.

## Regra principal

Desktop Commander não é dependência do fluxo.

Quando um chat/agente precisa executar build, Git, ADB, emulador, testes ou coletar logs no Windows, deve usar o BlackGold GitHub Runner quando ele estiver instalado.

## Descoberta do controle privado

O pacote público não contém o nome de nenhum repositório privado.

O instalador autenticado procura pelo arquivo exato:
`BLACKGOLD_RUNNER_CONTROL.json`

em repositórios privados acessíveis à conta GitHub local. O arquivo identifica o repositório de controle e a fila.

## Transporte

O Windows roda o GitHub Actions Self-Hosted Runner oficial registrado no repositório privado de controle.

Chats/agentes:
1. fazem mudanças de código no repositório do projeto;
2. criam um job JSON controlado na fila privada;
3. o workflow privado envia o job ao Windows;
4. o resultado volta nos logs do GitHub Actions;
5. o chat lê os logs pelo conector GitHub.

## Receitas permitidas

- status
- git_status
- git_sync
- gradle
- adb_devices
- adb_install
- adb_launch
- emulator_start
- logcat_tail

Não existe shell arbitrário.

## Instalação

O instalador:
- instala GitHub CLI via winget se necessário;
- autentica via GitHub CLI se ainda não houver sessão;
- descobre o repo privado pelo marcador;
- gera token temporário de runner para esse repo;
- baixa a release oficial atual de actions/runner;
- configura o runner;
- inicia no logon de forma oculta;
- verifica se o runner aparece online no GitHub.

O token de registro não é persistido.
