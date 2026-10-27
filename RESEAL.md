# Re-scellement des secrets Joutio

Statut : **re-scellé pour `joutio-prod` le 2026-10-27**. Les valeurs ont été régénérées
pour la mise en production Joutio (sauf Google/Resend, déjà rotationnés côté fournisseur,
et sauf le token Telegram et le token GHCR qui viennent de leurs fournisseurs).

## Source de vérité locale

Les valeurs sont stockées **hors du dépôt** dans :

```text
/Users/nadjim/Homeware/joutio-secrets/prod-secrets.env   (mode 0600)
```

Ce fichier ne doit **jamais** être commité ni affiché dans un terminal partagé. Il contient
les secrets générés (Postgres, JWK identity, client secrets OIDC, VAPID, MinIO, média,
Grafana admin, Google, Resend, GHCR).

> Le token Telegram ne peut pas être régénéré sans BotFather ; il est réutilisé.
> Le token GHCR provient de `gh auth token` (compte `CNadjim`).

## Facebook

Le fichier `apps/identity/facebook-sealed-secret.yml` a été **retiré** du dépôt tant que
l'application Meta n'est pas créée. Le `secretRef` correspondant dans
`apps/identity/manifests.yml` est déjà `optional: true` : identity démarre sans Facebook.

Quand Meta sera configuré :

```bash
export JOUTIO_OAUTH2_FACEBOOK_SECRET=...
./scripts/seal-secrets.sh identity-facebook
```

puis rajouter `facebook-sealed-secret.yml` dans `apps/identity/kustomization.yml`.

## Procédure de re-scellement

### 1. Récupérer le certificat public

Avec un kubeconfig local :

```bash
kubeseal --fetch-cert \
  --controller-name sealed-secrets \
  --controller-namespace sealed-secrets \
  > /tmp/joutio-sealed-secrets.pem
```

Sans kubeconfig, via le nœud k3s :

```bash
KEY=$(ssh pi@192.168.1.150 \
  'sudo k3s kubectl -n sealed-secrets get secret \
   -l sealedsecrets.bitnami.com/sealed-secrets-key=active -o json' \
  | jq -r '.items | sort_by(.metadata.creationTimestamp) | last | .metadata.name')

ssh pi@192.168.1.150 \
  "sudo k3s kubectl -n sealed-secrets get secret $KEY -o jsonpath='{.data.tls\.crt}'" \
  | base64 -d > /tmp/joutio-sealed-secrets.pem
```

### 2. Charger les valeurs et sceller

```bash
cd devops/joutio-gitops
set -a
source /Users/nadjim/Homeware/joutio-secrets/prod-secrets.env
set +a
export SEALED_SECRETS_CERT=/tmp/joutio-sealed-secrets.pem

# Apps + infrastructure
./scripts/seal-secrets.sh all

# Secrets hors `all`
./scripts/seal-secrets.sh identity-mail
./scripts/seal-secrets.sh identity-grafana
./scripts/seal-secrets.sh identity-argocd
./scripts/seal-secrets.sh argocd-oidc
./scripts/seal-secrets.sh argocd-repo-creds
./scripts/seal-secrets.sh argocd-registry
./scripts/seal-secrets.sh monitoring
```

`all` scelle `infra`, `ghcr-pull`, `identity`, les 9 services, `bff-push`, `minio` et
`bff-media`. Il saute `identity-facebook` si `JOUTIO_OAUTH2_FACEBOOK_SECRET` est absent.

### 3. Vérifier

```bash
# Aucun secret en clair (les valeurs ne sont pas affichées)
for f in $(git ls-files '*.yml'); do
  grep -q 'encryptedData' "$f" || continue
done

# Namespaces et noms
grep -R -A2 '^metadata:' apps/*/*sealed-secret.yml \
  argocd/config/sealed-secret.yml argocd/repo-creds/*.yml \
  monitoring/secrets/sealed-secret.yml infrastructure/*.yml | grep -E 'name:|namespace:'

# Build kustomize
for d in apps/*/ argocd/config argocd/repo-creds monitoring infrastructure; do
  kubectl kustomize "$d" >/dev/null || echo "KO $d"
done
```

## Points d'exploitation

- **VAPID** : la clé publique est dans `apps/bff/manifests.yml`
  (`JOUTIO_PUSH_VAPID_PUBLIC_KEY`) et doit correspondre à la clé privée scellée dans
  `apps/bff/push-sealed-secret.yml`. Une rotation invalide les abonnements Web Push
  existants.
- **ArgoCD OIDC** : `argocd/config` et `monitoring/secrets` sont **auto-synchronisés**
  sur le cluster. Après le déploiement de `joutio-prod`, il faut mettre à jour
  `argocd-secret` (`oidc.clientSecret`) et `argocd-cm` (`oidc.config`), puis redémarrer
  `argocd-server` (ou relancer le rôle `argocd_bootstrap`).
- **Grafana** : après application de `monitoring/secrets`, redémarrer le Deployment
  Grafana pour qu'il prenne le nouveau mot de passe admin et le nouveau client secret
  OIDC.
- **Ancien stack** : l'ancien namespace de production reste en place jusqu'à la validation
  complète de `joutio-prod`.

## Fichiers concernés

- `infrastructure/sealed-secret.yml`
- `infrastructure/registry-secret.yml`
- `apps/bff/push-sealed-secret.yml`
- `apps/bff/sealed-secret.yml`
- `apps/console/sealed-secret.yml`
- `apps/game/sealed-secret.yml`
- `apps/identity/sealed-secret.yml`
- `apps/identity/argocd-sealed-secret.yml`
- `apps/identity/grafana-sealed-secret.yml`
- `apps/identity/mail-sealed-secret.yml`
- `apps/leaderboard/sealed-secret.yml`
- `apps/matchmaking/sealed-secret.yml`
- `apps/minio/media-sealed-secret.yml`
- `apps/minio/sealed-secret.yml`
- `apps/notification/sealed-secret.yml`
- `apps/profile/sealed-secret.yml`
- `apps/social/sealed-secret.yml`
- `apps/theme/sealed-secret.yml`
- `argocd/config/sealed-secret.yml`
- `argocd/repo-creds/sealed-secret.yml`
- `argocd/repo-creds/registry-secret.yml`
- `monitoring/secrets/sealed-secret.yml`
