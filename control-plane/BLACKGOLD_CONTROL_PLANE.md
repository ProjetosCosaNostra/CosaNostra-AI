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
