# AGENTS.md — joutio-gitops

Manifests Kubernetes et ArgoCD (app-of-apps) du cluster k3s de production : infrastructure de
données, applications, addons, supervision. Les machines sont provisionnées par
`joutio-infrastructure`.

Lire : `../../AGENTS.md`, puis **[`docs/ops/exploitation.md`](../../docs/ops/exploitation.md)**
(arborescence, conventions, déploiement, configuration, remise à zéro, pièges) et
[`docs/ops/observabilite.md`](../../docs/ops/observabilite.md). Secrets : [`RESEAL.md`](RESEAL.md).

## Dans ce dépôt

| Dossier | Contenu |
|---|---|
| `argocd/` | `root-app.yml`, une Application par app et addon (`applications/`), config OIDC (`config/`), Image Updater, identifiants du dépôt |
| `infrastructure/` | Postgres (`postgres-init.yml` : une base `joutio_{service}` par service), Kafka KRaft, config commune, RBAC de découverte, secrets |
| `apps/<app>/` | `manifests.yml`, `kustomization.yml`, `sealed-secret.yml`, `autoscaling.yml` (HPA/PDB), ingress |
| `monitoring/` | ServiceMonitors, Probes, `prometheus-rules.yml`, exporters, `dashboards/`, datasources, `alertmanager-config.yml`, secrets |
| `scripts/` | `seal-secrets.sh <cible>`, `reset.sh [--yes] [--media]`, `reset-observability.sh` |

Apps : `bff`, `identity`, `theme`, `social`, `matchmaking`, `profile`, `game`, `leaderboard`,
`notification`, `console`, `joutio-web`, `joutio-web-console`, `joutio-landing`, `minio`.

## Règles

- Rien en clair : tout secret passe par `scripts/seal-secrets.sh`.
- Un nom unique par service, `joutio-<service>`, sauf `postgres`, `kafka` et `minio`. Les services
  Axon portent `app.kubernetes.io/component: axon` ; la console n'en a pas, car elle n'a pas de
  runtime Axon.
- Un Deployment piloté par HPA ne fixe pas `replicas`.
- Placement : chaque service préfère un nœud sans Postgres ni Kafka (anti-affinité `preferred` sur `app: postgres|kafka`),
  pas d'étalement par nœud. Les requests CPU suivent l'usage mesuré sous charge : le scheduler place sur elles.
- matchmaking et game : 1 réplique, groupes chauds segmentés dans le pod. Passer à 2 répliques n'a de sens qu'avec un
  nœud de plus ; ne jamais dépasser le nombre de segments de `joutio.axon.processors`.
- Sondes tolérantes à la saturation sur tous les services. Ne pas les resserrer sans mesure.
- Les tags d'image sont écrits par Image Updater (git write-back) : ne pas les éditer à la main.
- Un nouveau service exige :
  - sa base dans `postgres-init.yml` (sur un cluster déjà initialisé, la créer à la main ou faire
    un reset) ;
  - son Application ArgoCD ;
  - ses secrets scellés ;
  - son ServiceMonitor.

## Commandes

```bash
for d in apps/*/ argocd/config argocd/repo-creds monitoring infrastructure; do kubectl kustomize "$d" >/dev/null || echo "KO $d"; done
./scripts/seal-secrets.sh <cible>      # SEALED_SECRETS_CERT=./sealed-secrets-cert.pem
./scripts/reset.sh --yes               # efface Postgres + Kafka (voir docs/ops/exploitation.md)
```
