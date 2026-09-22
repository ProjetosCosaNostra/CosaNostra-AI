# BlackGold Control Plane

Fonte de verdade global do Ecossistema BlackGold para Windows, projetos e agentes.

## Contrato global

1. Nunca abrir janelas visíveis de CMD para automações do ecossistema.
2. Processos necessários devem continuar executando; janelas de `cmd.exe` são ocultadas, não encerradas.
3. PowerShell e processos auxiliares devem usar modo oculto/background quando tecnicamente possível.
4. Nenhum projeto deve depender de um serviço remoto de desktop para executar sua rotina local.
5. Este repositório é a fonte de verdade do Control Plane. Não duplicar regras em código de projeto.
6. Cada projeto deve conter um ponteiro `.blackgold/control-plane.json` ou `AGENTS.md` apontando para este contrato.
7. Após formatação do PC, reinstalar o agente local pelo bootstrap canônico; nenhuma cópia manual é necessária.
8. Nunca armazenar tokens, senhas ou segredos neste repositório.

## Componentes

- `manifest.json`: versão e URLs canônicas.
- `policies/windows.json`: política do Windows.
- `bootstrap.ps1`: reinstala/atualiza o agente local.
- `agent/BlackGold.Control.ps1`: agente residente oculto.
- `agent/Register-BlackGoldControl.ps1`: registra a tarefa de logon.
- `agent/Uninstall-BlackGoldControl.ps1`: remove somente o agente e sua tarefa.
- `project-pointer.json`: ponteiro que pode ser copiado para `.blackgold/control-plane.json`.

## Regra de CMD

O modo padrão é `hide_visible_cmd`. O agente enumera janelas de `cmd.exe` na sessão atual e aplica SW_HIDE. O processo não é morto.

Isso preserva:
- Gradle/Android builds;
- scripts .bat/.cmd;
- subprocessos de ferramentas;
- automações existentes.

A janela deixa de roubar foco ou cobrir o trabalho.

## Persistência

O estado canônico vive no GitHub. O componente local vive em:
`%LOCALAPPDATA%\BlackGold\ControlPlane`

A tarefa:
`BlackGold-ControlPlane`

inicia o agente em PowerShell oculto no logon do usuário.

## Uso por agentes/chats

Ao trabalhar em qualquer projeto BlackGold, procurar primeiro por:
1. `.blackgold/control-plane.json`
2. `AGENTS.md`
3. este contrato canônico no GitHub

Esses arquivos declaram que as regras globais têm precedência sobre automações locais, salvo instrução explícita do usuário no projeto atual.
