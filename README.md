# joutio-gitops

Dépôt GitOps (ArgoCD, app-of-apps) du cluster k3s de Joutio sur Raspberry Pi 5 (arm64). Il ne
contient que des manifests Kubernetes appliqués par ArgoCD ; les machines sont provisionnées par
`joutio-infrastructure` (Ansible).

Règles et contenu du dépôt : [`AGENTS.md`](AGENTS.md). Exploitation (domaines, déploiement, remise
à zéro, dépannage) : `docs/ops/` du workspace. Secrets : [`RESEAL.md`](RESEAL.md).
