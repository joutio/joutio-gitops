#!/usr/bin/env bash
#
# Génère les SealedSecrets du repo joutio-gitops.
#
# Prérequis :
#   export SEALED_SECRETS_CERT=./sealed-secrets-cert.pem   # kubeseal --fetch-cert > ...
#   kubectl + kubeseal disponibles
#
# Usage :
#   ./scripts/seal-secrets.sh all
#   ./scripts/seal-secrets.sh identity
#   ./scripts/seal-secrets.sh infra
#   ./scripts/seal-secrets.sh ghcr-pull
#   ./scripts/seal-secrets.sh monitoring
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
: "${SEALED_SECRETS_CERT:?SEALED_SECRETS_CERT doit pointer vers le certificat public sealed-secrets}"

seal_generic() {
  local ns="$1" name="$2" out="$3"
  shift 3
  kubectl create secret generic "${name}" --namespace "${ns}" "$@" \
    --dry-run=client -o json \
    | kubeseal --cert "${SEALED_SECRETS_CERT}" --format=yaml \
    > "${ROOT_DIR}/${out}"
  echo "sealed: ${out}"
}

seal_docker() {
  local ns="$1" name="$2" out="$3"
  shift 3
  kubectl create secret docker-registry "${name}" --namespace "${ns}" "$@" \
    --dry-run=client -o json \
    | kubeseal --cert "${SEALED_SECRETS_CERT}" --format=yaml \
    > "${ROOT_DIR}/${out}"
  echo "sealed: ${out}"
}

# Ajoute un SealedSecret à un fichier multi-documents (sans écraser le contenu existant).
append_sealed_generic() {
  local ns="$1" name="$2" out="$3"
  shift 3
  kubectl create secret generic "${name}" --namespace "${ns}" "$@" \
    --dry-run=client -o json \
    | kubeseal --cert "${SEALED_SECRETS_CERT}" --format=yaml \
    >> "${ROOT_DIR}/${out}"
  echo "sealed: ${out} (${name})"
}

# Secret client OAuth2 `server-client` (client_credentials) partagé par les services.
server_client_secret() {
  printf -- "--from-literal=SPRING_SECURITY_OAUTH2_CLIENT_REGISTRATION_SERVER_CLIENT_CLIENT_SECRET=%s" \
    "${IDENTITY_SERVER_CLIENT_SECRET:?IDENTITY_SERVER_CLIENT_SECRET manquant}"
}

seal_service() {
  local svc="$1"
  local upper
  upper="$(echo "${svc}" | tr '[:lower:]-' '[:upper:]_')"
  local var_db_pass="${upper}_DB_PASSWORD"
  # Un seul utilisateur Postgres `joutio` : tous les secrets DB doivent porter le MÊME
  # mot de passe que POSTGRES_PASSWORD (surchargeables via <SVC>_DB_PASSWORD si besoin).
  local db_pass="${!var_db_pass:-${INFRA_POSTGRES_PASSWORD:-}}"

  seal_generic joutio-prod "joutio-${svc}-secret" "apps/${svc}/sealed-secret.yml" \
    --from-literal=JOUTIO_DB_PASSWORD="${db_pass:?INFRA_POSTGRES_PASSWORD (ou ${var_db_pass}) manquant}" \
    "$(server_client_secret)"
}

# Secret additionnel du BFF : clé privée VAPID (Web Push). Séparé du secret principal pour ne
# pas avoir à le resceller en entier ; la clé publique va dans le ConfigMap `joutio-bff-config`.
seal_bff_push() {
  seal_generic joutio-prod joutio-bff-push apps/bff/push-sealed-secret.yml \
    --from-literal=JOUTIO_PUSH_VAPID_PRIVATE_KEY="${JOUTIO_PUSH_VAPID_PRIVATE_KEY:?JOUTIO_PUSH_VAPID_PRIVATE_KEY manquant}"
}

# Secret racine MinIO (StatefulSet + hook d'init `minio-init`).
seal_minio() {
  seal_generic joutio-prod joutio-minio-secret apps/minio/sealed-secret.yml \
    --from-literal=MINIO_ROOT_USER="${MINIO_ROOT_USER:?MINIO_ROOT_USER manquant}" \
    --from-literal=MINIO_ROOT_PASSWORD="${MINIO_ROOT_PASSWORD:?MINIO_ROOT_PASSWORD manquant}"
}

# Utilisateur applicatif MinIO du BFF (créé par le hook d'init, injecté dans le Deployment BFF).
seal_bff_media() {
  seal_generic joutio-prod joutio-bff-media apps/minio/media-sealed-secret.yml \
    --from-literal=JOUTIO_MEDIA_ACCESS_KEY="${JOUTIO_MEDIA_ACCESS_KEY:?JOUTIO_MEDIA_ACCESS_KEY manquant}" \
    --from-literal=JOUTIO_MEDIA_SECRET_KEY="${JOUTIO_MEDIA_SECRET_KEY:?JOUTIO_MEDIA_SECRET_KEY manquant}"
}

# Secret principal d'identity. Le client OAuth2 Google (login social) est REQUIS :
# sans `JOUTIO_OAUTH2_GOOGLE_SECRET`, le client-secret reste le placeholder littéral
# `${JOUTIO_OAUTH2_GOOGLE_SECRET}` et Google refuse l'échange de token.
seal_identity() {
  seal_generic joutio-prod joutio-identity-secret apps/identity/sealed-secret.yml \
    --from-literal=JOUTIO_DB_PASSWORD="${IDENTITY_DB_PASSWORD:-${INFRA_POSTGRES_PASSWORD:?INFRA_POSTGRES_PASSWORD manquant}}" \
    --from-literal=JOUTIO_IDENTITY_SERVER_CLIENT_SECRET="${IDENTITY_SERVER_CLIENT_SECRET:?IDENTITY_SERVER_CLIENT_SECRET manquant}" \
    --from-literal=JOUTIO_IDENTITY_ADMIN_CLIENT_SECRET="${IDENTITY_ADMIN_CLIENT_SECRET:?IDENTITY_ADMIN_CLIENT_SECRET manquant}" \
    --from-literal=JOUTIO_IDENTITY_JWK="${IDENTITY_JWK:-}" \
    --from-literal=JOUTIO_OAUTH2_GOOGLE_CLIENT_ID="${JOUTIO_OAUTH2_GOOGLE_CLIENT_ID:-270229696016-9u3916ckfcludqv77uiebgir65j3eurk.apps.googleusercontent.com}" \
    --from-literal=JOUTIO_OAUTH2_GOOGLE_SECRET="${JOUTIO_OAUTH2_GOOGLE_SECRET:?JOUTIO_OAUTH2_GOOGLE_SECRET manquant}"
}

# Secret additionnel d'identity : App Secret Facebook (login social web/mobile).
# Séparé du secret principal pour ne pas avoir à le resceller en entier.
seal_identity_facebook() {
  seal_generic joutio-prod joutio-identity-facebook apps/identity/facebook-sealed-secret.yml \
    --from-literal=JOUTIO_OAUTH2_FACEBOOK_SECRET="${JOUTIO_OAUTH2_FACEBOOK_SECRET:?JOUTIO_OAUTH2_FACEBOOK_SECRET manquant}"
}

# Secret additionnel d'identity : clé API Resend pour les codes de connexion OTP email.
# Séparé du secret principal pour ne pas avoir à le resceller en entier.
seal_identity_mail() {
  seal_generic joutio-prod joutio-identity-mail apps/identity/mail-sealed-secret.yml \
    --from-literal=JOUTIO_MAIL_API_KEY="${JOUTIO_MAIL_API_KEY:?JOUTIO_MAIL_API_KEY manquant}"
}

# Secret additionnel d'identity : client OIDC `grafana` (confidentiel).
# Séparé du secret principal pour ne pas avoir à le resceller en entier.
seal_identity_grafana() {
  seal_generic joutio-prod joutio-identity-grafana apps/identity/grafana-sealed-secret.yml \
    --from-literal=JOUTIO_GRAFANA_CLIENT_SECRET="${GRAFANA_OIDC_CLIENT_SECRET:?GRAFANA_OIDC_CLIENT_SECRET manquant}"
}

# Secret additionnel d'identity : client OIDC `argocd` (confidentiel).
# Séparé du secret principal pour ne pas avoir à le resceller en entier.
seal_identity_argocd() {
  seal_generic joutio-prod joutio-identity-argocd apps/identity/argocd-sealed-secret.yml \
    --from-literal=JOUTIO_ARGOCD_CLIENT_SECRET="${ARGOCD_OIDC_CLIENT_SECRET:?ARGOCD_OIDC_CLIENT_SECRET manquant}"
}

# Secret OIDC ArgoCD (namespace `argocd`) : lu par le rôle Ansible
# `argocd_bootstrap` pour renseigner `oidc.clientSecret` dans `argocd-secret`.
seal_argocd_oidc() {
  seal_generic argocd joutio-argocd-oidc argocd/config/sealed-secret.yml \
    --from-literal=client-secret="${ARGOCD_OIDC_CLIENT_SECRET:?ARGOCD_OIDC_CLIENT_SECRET manquant}"
}

seal_infra() {
  seal_generic joutio-prod joutio-infra-secret infrastructure/sealed-secret.yml \
    --from-literal=POSTGRES_PASSWORD="${INFRA_POSTGRES_PASSWORD:?INFRA_POSTGRES_PASSWORD manquant}"
}

seal_ghcr() {
  seal_docker joutio-prod ghcr-pull infrastructure/registry-secret.yml \
    --docker-server=ghcr.io \
    --docker-username="${GHCR_USERNAME:?GHCR_USERNAME manquant}" \
    --docker-password="${GHCR_TOKEN:?GHCR_TOKEN manquant}" \
    --docker-email="${GHCR_EMAIL:-unused@joutio.local}"
}

# Secrets de la stack d'observabilité (namespace `monitoring`).
seal_monitoring() {
  local out="monitoring/secrets/sealed-secret.yml"
  : > "${ROOT_DIR}/${out}"

  append_sealed_generic monitoring grafana-admin "${out}" \
    --from-literal=admin-user="${GRAFANA_ADMIN_USER:-admin}" \
    --from-literal=admin-password="${GRAFANA_ADMIN_PASSWORD:?GRAFANA_ADMIN_PASSWORD manquant}"

  append_sealed_generic monitoring grafana-oidc "${out}" \
    --from-literal=GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET="${GRAFANA_OIDC_CLIENT_SECRET:?GRAFANA_OIDC_CLIENT_SECRET manquant}"

  append_sealed_generic monitoring telegram-alertmanager "${out}" \
    --from-literal=bot-token="${TELEGRAM_BOT_TOKEN:?TELEGRAM_BOT_TOKEN manquant}"
}

seal_all() {
  seal_infra
  seal_ghcr
  seal_identity
  seal_identity_facebook
  for svc in theme game social matchmaking profile leaderboard notification console bff; do
    seal_service "${svc}"
  done
  seal_bff_push
  seal_minio
  seal_bff_media
}

case "${1:-all}" in
  all) seal_all ;;
  identity) seal_identity ;;
  identity-facebook) seal_identity_facebook ;;
  identity-mail) seal_identity_mail ;;
  identity-grafana) seal_identity_grafana ;;
  identity-argocd) seal_identity_argocd ;;
  argocd-oidc) seal_argocd_oidc ;;
  infra) seal_infra ;;
  ghcr-pull) seal_ghcr ;;
  monitoring) seal_monitoring ;;
  theme|game|social|matchmaking|profile|leaderboard|notification|console|bff) seal_service "$1" ;;
  bff-push) seal_bff_push ;;
  minio) seal_minio ;;
  bff-media) seal_bff_media ;;
  *)
    echo "usage: $0 [all|infra|ghcr-pull|monitoring|identity|identity-facebook|identity-mail|identity-grafana|identity-argocd|argocd-oidc|theme|game|social|matchmaking|profile|leaderboard|notification|console|bff|bff-push|minio|bff-media]" >&2
    exit 1
    ;;
esac
