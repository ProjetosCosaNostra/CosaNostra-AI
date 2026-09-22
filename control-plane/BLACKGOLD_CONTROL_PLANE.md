# BlackGold Control Plane

Fonte de verdade global do Ecossistema BlackGold para Windows, projetos e agentes.

## Contrato global

1. Nunca abrir janelas visíveis de CMD para automações do ecossistema.
2. Processos necessários devem continuar executando; janelas de `cmd.exe` são ocultadas, não encerradas.
3. PowerShell e processos auxiliares devem usar modo oculto/background quando tecnicamente possível.
4. Nenhum projeto deve depender de serviço remoto de desktop para executar sua rotina local.
5. Este repositório é a fonte de verdade do Control Plane. Não duplicar regras em código de projeto.
6. Cada projeto deve conter um ponteiro `.blackgold/control-plane.json` ou `AGENTS.md` apontando para este contrato.
7. Após formatação do PC, reinstalar o agente local pelo bootstrap canônico; nenhuma cópia manual é necessária.
8. Nunca armazenar tokens, senhas ou segredos neste repositório.

## Componentes

- `manifest.json`: versão e URLs canônicas.
- `policies/windows.json`: política do Windows.
- `bootstrap.ps1`: reinstala/atualiza o agente local.
- `agent/BlackGold.Control.ps1`: agente residente oculto.
- `agent/Register-BlackGoldControl.ps1`: registra inicialização e fallback do usuário.
- `agent/Uninstall-BlackGoldControl.ps1`: remove a inicialização do agente.
- `Register-BlackGoldProjects.ps1`: registra projetos locais do ecossistema.
- `Status-BlackGoldControl.ps1`: diagnóstico canônico de saúde.
- `Repair-BlackGoldControl.ps1`: reinstala/repara a partir do GitHub.
- `project-pointer.json`: ponteiro para `.blackgold/control-plane.json`.

## Regra de CMD

O modo padrão é `hide_visible_cmd`.

O agente:
- detecta janelas visíveis de `cmd.exe`;
- aplica `SW_HIDE` sem encerrar o processo;
- preserva Gradle, Android builds, scripts .bat/.cmd e subprocessos;
- registra PID, processo pai e linha de comando para descobrir a origem;
- mantém logs locais com retenção configurável.

## Autorreparo

O modo preferencial usa a tarefa `BlackGold-ControlPlane` no logon com reinício automático.
Se o Agendador não puder ser usado, o sistema registra fallback em `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`.

O comando de reparo sempre baixa novamente a versão canônica do GitHub e reaplica o bootstrap.

## Persistência

O estado canônico vive no GitHub.
O componente local vive em:
`%LOCALAPPDATA%\BlackGold\ControlPlane`

Após formatação, o repositório continua sendo a fonte de verdade e o bootstrap reconstrói o componente local.

## Uso por agentes/chats

Ao trabalhar em qualquer projeto BlackGold, procurar primeiro por:
1. `.blackgold/control-plane.json`
2. `AGENTS.md`
3. este contrato canônico no GitHub

Esses arquivos declaram as regras globais de execução do ecossistema. Alterações locais não devem reintroduzir CMD visível.
