# BlackGold Control Plane

Fonte de verdade global do Ecossistema BlackGold para Windows, projetos e agentes.

## Contrato global

1. Nunca abrir janelas visíveis de CMD para automações do ecossistema.
2. Processos necessários devem continuar executando; janelas de `cmd.exe` são ocultadas, não encerradas.
3. PowerShell e processos auxiliares devem usar modo oculto/background quando tecnicamente possível.
4. Nenhum projeto deve depender de serviço remoto de desktop para executar sua rotina local.
5. Este repositório é a fonte de verdade do Control Plane. Não duplicar regras em código de projeto.
6. Cada projeto deve conter `.blackgold/control-plane.json` ou `AGENTS.md` apontando para este contrato.
7. Após formatação do PC, reinstalar pelo endpoint permanente `install.ps1`; nenhuma cópia manual é necessária.
8. Nunca armazenar tokens, senhas ou segredos neste repositório.

## Instalação permanente

O endereço de instalação não muda entre versões:

`control-plane/install.ps1`

Ele consulta `LATEST.json`, descobre a versão estável vigente e executa o bootstrap correto. O usuário não precisa saber se a versão atual é 1.2, 1.5 ou posterior.

## Atualização automática

`Update-BlackGoldControl.ps1` compara a versão local com `LATEST.json`.

Quando há versão nova, ele reaplica o bootstrap canônico. A inicialização registra:
- `BlackGold-ControlPlane`: agente residente;
- `BlackGold-ControlPlane-Update`: verificação automática no logon e diariamente.

Se o Agendador não puder ser usado, existe fallback em `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`.

## Regra de CMD

O agente:
- detecta janelas visíveis de `cmd.exe`;
- aplica `SW_HIDE` sem encerrar o processo;
- preserva Gradle, Android builds, scripts .bat/.cmd e subprocessos;
- registra PID, processo pai e linha de comando para descobrir a origem;
- mantém logs locais com retenção configurável.

## Diagnóstico e reparo

- `Status-BlackGoldControl.ps1`: informa versão local, versão mais recente, processo residente, método de inicialização e últimos CMD detectados.
- `Repair-BlackGoldControl.ps1`: busca novamente o bootstrap canônico e repara a instalação.

## Persistência

O estado canônico vive no GitHub.
O componente local vive em:
`%LOCALAPPDATA%\BlackGold\ControlPlane`

Uma formatação apaga o componente local, mas não a fonte canônica. O instalador permanente reconstrói o sistema a partir do GitHub.

## Uso por agentes/chats

Ao trabalhar em qualquer projeto BlackGold, procurar primeiro por:
1. `.blackgold/control-plane.json`
2. `AGENTS.md`
3. este contrato canônico no GitHub

Alterações locais não devem reintroduzir CMD visível nem substituir a fonte central de regras.


## Canal estável validado

O runtime do Windows não consome a branch `main` diretamente.

A branch `control-plane-stable` contém somente commits promovidos depois de validação completa.

Fluxo:
1. desenvolvimento ocorre em branch de trabalho;
2. CI valida PowerShell, JSON, invariantes e coerência de versão;
3. a mudança é mesclada na `main`;
4. somente após o CI da `main` concluir com sucesso, o commit é promovido para `control-plane-stable`;
5. instalação, update, reparo, status e Doctor leem apenas `control-plane-stable`.

Isso elimina downloads de versões parcialmente atualizadas.


## Instalação transacional

A partir da v1.5.0, o Control Plane não atualiza mais a instalação ativa arquivo por arquivo.

Slots locais:
- `ControlPlane`: instalação ativa.
- `ControlPlane.__staging`: versão em preparação.
- `ControlPlane.__previous`: última versão ativa conhecida e preservada para rollback.
- `ControlPlane.transaction.json`: journal da última transação.

Fluxo:
1. baixar todos os arquivos do canal estável para staging;
2. validar JSONs, coerência de versão e sintaxe de todos os scripts PowerShell;
3. interromper somente os componentes do próprio Control Plane;
4. mover a instalação ativa para o slot anterior;
5. promover staging para ativo;
6. registrar agente/updater/Doctor e executar health check;
7. marcar a transação como committed;
8. se qualquer etapa após a promoção falhar, restaurar automaticamente o slot anterior.

O Doctor tenta rollback local antes de depender de download remoto quando identifica corrupção ou falha local da instalação.


## Integridade por commit imutável

A partir da v1.6.0, nenhuma instalação depende de uma branch móvel durante o download.

Fluxo de integridade:
1. resolver `control-plane-stable` para um SHA de commit exato;
2. obter a árvore Git desse commit;
3. baixar todos os arquivos usando o SHA imutável do commit;
4. recalcular localmente a identidade Git blob de cada arquivo;
5. comparar com o blob registrado na árvore Git;
6. gravar `install-state.json` com commit, tree SHA e quantidade de arquivos verificados;
7. somente depois permitir a promoção do staging para ativo.

Se um arquivo estiver vazio, alterado ou não corresponder ao blob esperado, a transação falha antes de tocar na instalação ativa.

Essa verificação usa a identidade de objeto Git do repositório e HTTPS. Ela é uma checagem de integridade/content-addressing, não uma assinatura criptográfica independente.


## Transporte local por GitHub Runner

A partir da v1.7.0, o Ecossistema BlackGold possui um transporte oficial para execução local sem depender de Desktop Commander.

O pacote canônico vive em:
`control-plane/github-runner`

O pacote:
- usa o GitHub Actions Self-Hosted Runner oficial;
- descobre o repositório privado de controle pelo marcador autenticado `BLACKGOLD_RUNNER_CONTROL.json`;
- registra o runner nesse repositório;
- inicia o listener escondido no logon;
- restringe a execução a receitas controladas;
- usa jobs privados e devolve resultados pelos logs do GitHub Actions.

Desktop Commander pode existir como ferramenta auxiliar, mas nunca deve ser tratado como pré-requisito para continuar um projeto quando o GitHub Runner estiver disponível.
