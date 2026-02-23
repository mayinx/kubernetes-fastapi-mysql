#!/usr/bin/env bash
set -euo pipefail

# capture-proof.sh
# Creates a timestamped proof bundle under: evidence/<YYYY-MM-DD_HHMM>/
# Each file is numbered so the order is obvious and easy to review.

TS="$(date +%Y-%m-%d_%H%M)"
OUTDIR="evidence/${TS}"
mkdir -p "$OUTDIR"

echo "Writing proof to: $OUTDIR"

# -----------------------------------------------------------------------------
# 00_meta.txt — run metadata (timestamp + BASE_URL used for curl checks)
# BASE_URL can be provided explicitly:
#   BASE_URL="http://<INGRESS_IP>" ./scripts/capture-proof.sh
# If BASE_URL is not provided, we derive it from the Ingress status.
# If we cannot derive it, we write the meta file, print a short instruction, and exit.
# -----------------------------------------------------------------------------
BASE_URL="${BASE_URL:-}"

if [ -z "$BASE_URL" ]; then
  INGRESS_IP="$(kubectl get ingress api-ingress -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"
  INGRESS_HOST="$(kubectl get ingress api-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"

  if [ -n "$INGRESS_IP" ]; then
    BASE_URL="http://${INGRESS_IP}"
  elif [ -n "$INGRESS_HOST" ]; then
    BASE_URL="http://${INGRESS_HOST}"
  fi
fi

# 00_meta.txt — minimal run metadata to tie the evidence bundle to a specific cluster + repo state
{
  echo "timestamp=${TS}"
  echo "base_url=${BASE_URL}"
  echo "kube_context=$(kubectl config current-context)"
  echo "namespace=default"
  echo "git_commit=$(git rev-parse --short HEAD 2>/dev/null || echo '<no-git>')"
  echo "kubectl_client_version=$(kubectl version --client 2>/dev/null | tr -s ' ')"
} > "$OUTDIR/00_meta.txt"

# If we cannot detect an Ingress address and the user didn't provide BASE_URL,
# we cannot run the curl checks. Print next steps and exit with failure.
if [ -z "$BASE_URL" ]; then
  echo "ERROR: Could not detect an Ingress address for api-ingress (no IP/hostname in status)." >&2
  echo "Next steps:" >&2
  echo "  1) Inspect Ingress: kubectl get ingress api-ingress -o wide" >&2
  echo "  2) Fallback via port-forward:" >&2
  echo "     kubectl port-forward svc/api-svc 8000:8000" >&2
  echo "     BASE_URL=http://localhost:8000 ./scripts/capture-proof.sh" >&2
  exit 1
fi

# -----------------------------------------------------------------------------
# 01_pods.txt — Pods for the Deployment (replicas + Ready 2/2 per Pod)
# -----------------------------------------------------------------------------
kubectl get pods -l app=api-mysql -o wide > "$OUTDIR/01_pods.txt"

# -----------------------------------------------------------------------------
# 02_service.txt — Service details (ClusterIP + port 8000 -> targetPort 8000)
# -----------------------------------------------------------------------------
kubectl get svc api-svc -o wide > "$OUTDIR/02_service.txt"

# -----------------------------------------------------------------------------
# 03_endpointslice.txt — resolved backend endpoints (Pod IPs:8000 behind the Service)
# -----------------------------------------------------------------------------
kubectl get endpointslice -l kubernetes.io/service-name=api-svc -o wide > "$OUTDIR/03_endpointslice.txt"

# -----------------------------------------------------------------------------
# 04_ingress.txt — Ingress status (ADDRESS/hostname + class)
# -----------------------------------------------------------------------------
kubectl get ingress api-ingress -o wide > "$OUTDIR/04_ingress.txt"

# -----------------------------------------------------------------------------
# 05/06/07 — API responses (via detected BASE_URL)
# -----------------------------------------------------------------------------
curl -s "${BASE_URL}/status"  > "$OUTDIR/05_curl_status.txt"
curl -s "${BASE_URL}/users"   > "$OUTDIR/06_curl_users.json"
curl -s "${BASE_URL}/users/1" > "$OUTDIR/07_curl_user_1.json"

echo "Done."