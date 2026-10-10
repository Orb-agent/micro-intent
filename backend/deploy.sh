#!/usr/bin/env bash
# Deploy the backend to Cloud Run from source (Cloud Build builds the image remotely; no local Docker).
# Uses explicit --project/--region flags and never changes the local gcloud configuration.
#
#   backend/deploy.sh                      # defaults below
#   REGION=europe-west1 backend/deploy.sh  # override any variable
#
# The Gemini key goes to Secret Manager; it is read from $ENV_FILE only if the secret does not exist yet.
set -euo pipefail

PROJECT="${PROJECT:-agentic26zrh-2067}"
REGION="${REGION:-europe-west6}"
SERVICE="${SERVICE:-micro-intent-backend}"
SECRET="${SECRET:-micro-intent-gemini-key}"
ENV_FILE="${ENV_FILE:-$HOME/.config/micro-intent/gemini.env}"
MODEL="${MICRO_INTENT_MODEL:-gemini-3.8-flash}"
LIVE_MODEL="${MICRO_INTENT_LIVE_MODEL:-gemini-3.8-live}"
CALENDAR_SOURCE="${CALENDAR_SOURCE:-mock}"

here="$(cd "$(dirname "$0")" && pwd)"
gc=(--project "$PROJECT" --quiet)

echo "==> enabling APIs on $PROJECT"
gcloud services enable run.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com secretmanager.googleapis.com "${gc[@]}"

if ! gcloud secrets describe "$SECRET" "${gc[@]}" >/dev/null 2>&1; then
  echo "==> creating secret $SECRET from $ENV_FILE"
  key="$(set -a; . "$ENV_FILE"; set +a; printf %s "${GEMINI_API_KEY:-${GOOGLE_API_KEY:-}}")"
  [ -n "$key" ] || { echo "no GEMINI_API_KEY in $ENV_FILE" >&2; exit 1; }
  printf %s "$key" | gcloud secrets create "$SECRET" --data-file=- --replication-policy=automatic "${gc[@]}"
  unset key
fi

number="$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')"
runtime_sa="${number}-compute@developer.gserviceaccount.com"
echo "==> granting $runtime_sa access to $SECRET"
gcloud secrets add-iam-policy-binding "$SECRET" --member="serviceAccount:$runtime_sa" \
  --role=roles/secretmanager.secretAccessor "${gc[@]}" >/dev/null

# Pending actions, profile and the mock calendar live in memory: exactly one instance, always warm.
echo "==> deploying $SERVICE to $REGION"
gcloud run deploy "$SERVICE" \
  --source "$here" \
  --region "$REGION" \
  --allow-unauthenticated \
  --min-instances 1 --max-instances 1 \
  --cpu 1 --memory 512Mi --concurrency 40 --timeout 120 \
  --set-secrets "GEMINI_API_KEY=$SECRET:latest" \
  --set-env-vars "MICRO_INTENT_MODEL=$MODEL,MICRO_INTENT_LIVE_MODEL=$LIVE_MODEL,CALENDAR_SOURCE=$CALENDAR_SOURCE,MICRO_INTENT_TZ=Europe/Zurich" \
  "${gc[@]}"

url="$(gcloud run services describe "$SERVICE" --region "$REGION" --format='value(status.url)' --project "$PROJECT")"
echo "==> $url"
curl -fsS "$url/health" && echo
