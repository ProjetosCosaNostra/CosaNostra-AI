# BlackGold Control Plane — Public/Private Data Boundary

The canonical Control Plane repository is public. Therefore:

- Public Control Plane files may describe public repositories.
- Names of private repositories must not be exported into public registry files.
- The complete repository inventory, when needed, must live in an authenticated private repository.
- Agents with authenticated GitHub access may search for the exact private inventory filename:
  `BLACKGOLD_PRIVATE_PROJECT_REGISTRY.json`
- Never copy credentials, secrets, tokens, private URLs, or private repository names into public Control Plane files.

This rule is enforced by the Control Plane validation workflow.
