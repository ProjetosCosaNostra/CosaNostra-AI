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
