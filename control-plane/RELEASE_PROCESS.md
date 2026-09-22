# BlackGold Control Plane Release Process

## Objetivo

Nunca expor clientes Windows a um Control Plane parcialmente atualizado.

## Branches

- `main`: histórico de integração validada.
- `control-plane-stable`: canal consumido por instalação, update, reparo, Doctor e status.
- branches de feature/release: todo desenvolvimento.

## Sequência de promoção

1. Criar uma branch de release a partir de `main`.
2. Aplicar todas as mudanças e versões nessa branch.
3. Aguardar **BlackGold Control Plane Validate** concluir com sucesso.
4. Abrir pull request para `main`.
5. Mesclar somente após validação do PR.
6. O workflow de promoção aguarda a validação da `main`.
7. Apenas então `control-plane-stable` avança para o commit exato validado.

## Rollback

Se uma versão promovida apresentar defeito, mover `control-plane-stable` para o último commit conhecido e validado. Os clientes passam a ler novamente a versão anterior no próximo ciclo de instalação, update ou reparo.

## Invariantes

- Runtime não busca payloads da `main`.
- `LATEST.json`, `manifest.json`, `CURRENT_TRUTH.json` e `PROJECT_REGISTRY.json` usam a mesma versão.
- Nomes de repositórios privados não entram no registro público.
- Estar na `main` não significa estar em produção; produção significa estar em `control-plane-stable`.
