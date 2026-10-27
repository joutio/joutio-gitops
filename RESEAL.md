# Re-scellement des secrets Joutio

Les `SealedSecret` de ce dépôt ont été chiffrés pour l'ancien namespace de production et les
anciens noms de secrets. Un `SealedSecret` est lié au **namespace** et au **nom** : après le
renommage vers `joutio-prod`, les `encryptedData` actuels ne peuvent plus être déchiffrés.

**Ne pas appliquer ces fichiers tels quels.** Ils doivent être re-scelés avant le premier
déploiement du stack Joutio.

## Procédure

1. Récupérer le certificat public du contrôleur `sealed-secrets` :

   ```bash
   kubeseal --fetch-cert \
     --controller-name sealed-secrets \
     --controller-namespace sealed-secrets \
     > /tmp/joutio-sealed-secrets.pem
   ```

2. Charger les valeurs depuis la source de vérité (1Password/Doppler), puis utiliser le script
   fourni :

   ```bash
   export SEALED_SECRETS_CERT=/tmp/joutio-sealed-secrets.pem
   export INFRA_POSTGRES_PASSWORD=...
   export IDENTITY_SERVER_CLIENT_SECRET=...
   export IDENTITY_ADMIN_CLIENT_SECRET=...
   export JOUTIO_OAUTH2_GOOGLE_SECRET=...
   export JOUTIO_OAUTH2_FACEBOOK_SECRET=...
   export JOUTIO_MAIL_API_KEY=...
   export GRAFANA_OIDC_CLIENT_SECRET=...
   export ARGOCD_OIDC_CLIENT_SECRET=...
   export JOUTIO_PUSH_VAPID_PRIVATE_KEY=...
   export MINIO_ROOT_USER=...
   export MINIO_ROOT_PASSWORD=...
   export JOUTIO_MEDIA_ACCESS_KEY=...
   export JOUTIO_MEDIA_SECRET_KEY=...
   export GHCR_USERNAME=...
   export GHCR_TOKEN=...
   export GRAFANA_ADMIN_PASSWORD=...
   export TELEGRAM_BOT_TOKEN=...

   ./scripts/seal-secrets.sh all
   ```

3. Les secrets optionnels (non inclus dans `all`) :

   ```bash
   ./scripts/seal-secrets.sh identity-mail
   ./scripts/seal-secrets.sh identity-grafana
   ./scripts/seal-secrets.sh identity-argocd
   ./scripts/seal-secrets.sh argocd-oidc
   ```

4. Vérifier pour chaque fichier :
   - `metadata.namespace: joutio-prod` (ou `argocd`/`monitoring` selon le cas) ;
   - des clés `encryptedData` en `JOUTIO_*` (ou les clés techniques attendues) ;
   - aucun secret en clair.

## Fichiers concernés

- `apps/bff/push-sealed-secret.yml`
- `apps/bff/sealed-secret.yml`
- `apps/console/sealed-secret.yml`
- `apps/game/sealed-secret.yml`
- `apps/identity/argocd-sealed-secret.yml`
- `apps/identity/facebook-sealed-secret.yml`
- `apps/identity/grafana-sealed-secret.yml`
- `apps/identity/mail-sealed-secret.yml`
- `apps/identity/sealed-secret.yml`
- `apps/leaderboard/sealed-secret.yml`
- `apps/matchmaking/sealed-secret.yml`
- `apps/minio/media-sealed-secret.yml`
- `apps/minio/sealed-secret.yml`
- `apps/notification/sealed-secret.yml`
- `apps/profile/sealed-secret.yml`
- `apps/social/sealed-secret.yml`
- `apps/theme/sealed-secret.yml`
- `argocd/config/sealed-secret.yml`
- `argocd/repo-creds/registry-secret.yml`
- `argocd/repo-creds/sealed-secret.yml`
- `infrastructure/registry-secret.yml`
- `infrastructure/sealed-secret.yml`
- `monitoring/secrets/sealed-secret.yml`
