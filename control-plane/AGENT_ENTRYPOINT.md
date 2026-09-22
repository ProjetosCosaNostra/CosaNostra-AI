# BlackGold Agent Entrypoint

Este arquivo é o ponto de entrada canônico para qualquer agente/chat que trabalhe em um projeto do Ecossistema BlackGold.

## Ordem obrigatória de leitura

1. Leia `control-plane/CURRENT_TRUTH.json`.
2. Leia `control-plane/BLACKGOLD_CONTROL_PLANE.md`.
3. Leia `control-plane/PROJECT_REGISTRY.json`.
4. No repositório do projeto atual, leia `AGENTS.md`.
5. No repositório do projeto atual, leia `.blackgold/control-plane.json`.

## Regra operacional principal

Nunca introduza automações que abram uma janela visível de `cmd.exe` para o usuário. Quando um processo CMD for necessário para build, Gradle, Android ou scripts, preserve o processo e execute/oculte a interface conforme a política central.

## Continuidade

Não recomece trabalho concluído. Antes de alterar automação, runners, bootstrap, emulador ou processos locais, consulte o estado canônico.

## Novos repositórios

Todo novo repositório BlackGold deve receber:
- `AGENTS.md`
- `.blackgold/control-plane.json`

e ser incluído em `control-plane/PROJECT_REGISTRY.json`.

A fonte de verdade é:
`ProjetosCosaNostra/CosaNostra-AI/control-plane`.


## Inventário privado

O registro público nunca deve expor nomes de repositórios privados.

Quando inventário completo for realmente necessário e houver um conector GitHub autenticado, procure pelo nome exato:
`BLACKGOLD_PRIVATE_PROJECT_REGISTRY.json`

Use esse inventário apenas dentro do contexto autenticado. Não copie nomes privados para arquivos públicos do Control Plane.


## Regra de release

Não desenvolver mudanças do Control Plane diretamente no canal estável.

Use branch de trabalho, valide, mescle na `main` e só então promova o commit validado para `control-plane-stable`. O runtime local deve ler apenas o canal estável.


## Execução remota pelo GitHub Runner

Desktop Commander não é dependência obrigatória do Ecossistema BlackGold.

Quando uma tarefa exigir execução no Windows local:

1. Não espere Desktop Commander ficar online.
2. Liste os repositórios acessíveis pelo conector GitHub autenticado.
3. Em cada repositório privado acessível, tente ler `BLACKGOLD_RUNNER_CONTROL.json` na raiz. Não dependa de code search; o índice pode atrasar ou não retornar privados.
4. Quando encontrar um marcador cujo campo `system` seja `BlackGold GitHub Runner Control`, leia `queue_path` e `workflow`.
5. Crie um job JSON com `request_id` único e uma das receitas permitidas pelo schema canônico.
6. Aguarde o workflow `BlackGold Windows Job Queue`.
7. Leia os logs do workflow pelo conector GitHub.
8. Use o resultado para continuar o trabalho do projeto.

Mudanças de código devem ser feitas no repositório do projeto. A fila local deve executar operações controladas como sync, Gradle, ADB, emulador, testes e coleta de logs.

Não criar shell arbitrário, scripts codificados em Base64 ou comandos livres dentro da fila.
