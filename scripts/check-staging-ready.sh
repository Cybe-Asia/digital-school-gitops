#!/usr/bin/env bash
# Quick sanity check: is lab/staging ready for a skip_cutover test-on-idle?
#
# Reports:
#   - image tags currently pinned in lab/staging/kustomization.yaml
#   - last commits touching that file (so you can correlate with service pushes)
#   - whether the auto-promote-lab cascade reached staging recently
#   - optional external smoke if staging.school.cybe.tech resolves
#   - optional ArgoCD check if argocd CLI is logged in
#
# Run from anywhere:
#   ./scripts/check-staging-ready.sh
#
# Expected image tag format AFTER the path-rename migration: sha-<7 hex>
# Legacy tags from before migration: dev-<7 hex> (will be overwritten by next
# cascade from main).

set -eu

cd "$(dirname "$0")/.."

echo "📥 git pull origin main --quiet"
git pull --quiet origin main

echo
echo "=== 1. Image tags in lab/staging/kustomization.yaml ==="
awk '
  /^images:/ { flag=1; next }
  flag && /^- name:/ { name=$3 }
  flag && /newTag:/  {
    tag=$2
    status="⚠️  legacy (pre-migration)"
    if (tag ~ /^sha-/) status="✅ post-migration"
    printf "  %-48s → %-12s %s\n", name, tag, status
  }
' lab/staging/kustomization.yaml

echo
echo "=== 2. Last 5 commits touching lab/staging/kustomization.yaml ==="
git log --oneline -5 --since="7 days ago" -- lab/staging/kustomization.yaml || \
  git log --oneline -5 -- lab/staging/kustomization.yaml

echo
echo "=== 3. External smoke on staging subdomain (if DNS resolves) ==="
if host staging.school.cybe.tech >/dev/null 2>&1; then
  code=$(curl -sk --max-time 5 -o /dev/null -w "%{http_code}" \
    https://staging.school.cybe.tech:8443/ 2>/dev/null || true)
  code=${code:-000}
  case "$code" in
    200|301|302|303) echo "  ✅ staging reachable: HTTP $code" ;;
    000) echo "  ❌ connection failed (port blocked / TLS issue)" ;;
    *) echo "  ⚠️  staging responded HTTP $code" ;;
  esac
else
  echo "  ℹ️  staging.school.cybe.tech not in public DNS — skipping."
  echo "     (staging may be internal-only; verify via ArgoCD or kubectl instead)"
fi

echo
echo "=== 4. ArgoCD status via API (if creds available) ==="
if [ -n "${ARGOCD_URL:-}" ] && [ -n "${ARGOCD_TOKEN:-}" ]; then
  curl -sk -H "Authorization: Bearer $ARGOCD_TOKEN" \
    "$ARGOCD_URL/api/v1/applications/school-staging-services" | \
    jq -r '"  sync=\(.status.sync.status)  health=\(.status.health.status)  operationPhase=\(.status.operationState.phase // "idle")"' 2>/dev/null || \
    echo "  ⚠️  API call failed"
elif command -v argocd >/dev/null 2>&1; then
  argocd app get school-staging-services --grpc-web 2>/dev/null | \
    grep -E "Sync Status|Health Status|Images" || \
    echo "  (argocd CLI not logged in — check https://argo.cybe.tech:8443/ manually)"
else
  echo "  ℹ️  no argocd CLI, no ARGOCD_URL/ARGOCD_TOKEN env vars"
  echo "     set ARGOCD_URL=https://... and ARGOCD_TOKEN=... to enable this check"
  echo "     or check UI: https://argo.cybe.tech:8443/applications/school-staging-services"
fi

echo
echo "=== 5. GitHub Actions last auto-promote-lab run (needs gh CLI) ==="
if command -v gh >/dev/null 2>&1; then
  gh run list --workflow=auto-promote-lab.yml --limit 3 \
    --repo Cybe-Asia/digital-school-gitops \
    --json status,conclusion,createdAt,headSha \
    --template '{{range .}}  {{.status}}  {{.conclusion}}  {{.createdAt}}  {{.headSha | truncate 7}}{{"\n"}}{{end}}' \
    2>/dev/null || echo "  (gh CLI not authenticated against Cybe-Asia)"
else
  echo "  (gh CLI not installed — check https://github.com/Cybe-Asia/digital-school-gitops/actions)"
fi

echo
echo "=== Verdict ==="
echo "Ready for test-on-idle if:"
echo "  ☐ image tags show sha-<hex> (post-migration) matching your recent push"
echo "  ☐ last auto-promote-lab run succeeded (section 5) within last ~15 min"
echo "  ☐ school-staging-services is Synced/Healthy (section 4)"
echo ""
echo "If all three ☑, go to:"
echo "  https://github.com/Cybe-Asia/digital-school-gitops/actions/workflows/auto-promote-prod.yml"
echo "  → Run workflow → reason=\"...\" → skip_cutover=true"
