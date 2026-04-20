# Observability

What you have, where it lives, how to use it.

## Stack

| Component | Namespace | Purpose | URL |
|---|---|---|---|
| Prometheus | `monitoring` | Metrics storage | via Grafana |
| Grafana | `monitoring` | Dashboards + Explore | https://grafana.cybe.tech:8443/ |
| Alertmanager | `monitoring` | Alert routing | via Grafana |
| Loki | `monitoring` | Log aggregation | via Grafana |
| Promtail | `monitoring` (daemonset) | Log shipping from nodes | — |
| Argo CD | `platform-system` | Sync status | https://argo.cybe.tech:8443/ |

## Metrics — Prometheus via Grafana

### Cluster-level views (default dashboards)

- `Kubernetes / Compute Resources / Namespace (Pods)` — per-pod CPU/mem in a ns
- `Kubernetes / Compute Resources / Pod` — drill into one specific pod
- `Node Exporter / Nodes` — per-node health (R250, R630)
- `Alertmanager / Overview` — active alerts

### School-specific

- `School Domain Overview` — CPU/mem/restarts/PVC/quota/pods per school-* namespace
- Alerts (school-specific): `SchoolPodCrashLoopBackOff`, `SchoolPVCAlmostFull`, `SchoolNeo4jDown`, `SchoolBackupJobFailed`, `SchoolNamespaceQuotaExhausting`

### Useful PromQL (paste into Explore → Prometheus)

```promql
# CPU rate per school env
sum by (namespace) (rate(container_cpu_usage_seconds_total{namespace=~"school-.*", container!=""}[5m]))

# Memory per service in prod-blue
sum by (pod) (container_memory_working_set_bytes{namespace="school-prod-blue", container!=""})

# Pod restart count
sum by (pod) (kube_pod_container_status_restarts_total{namespace=~"school-prod-.*"})

# Neo4j up status per env
up{namespace=~"school-.*", pod=~"neo4j-.*"}

# PVC utilisation
kubelet_volume_stats_used_bytes / kubelet_volume_stats_capacity_bytes
```

## Logs — Loki via Grafana

Explore → data source: **Loki** → use LogQL.

### Common queries

```logql
# All logs from a specific service
{namespace="school-prod-blue", container="auth-service"}

# Errors across all school prod
{namespace=~"school-prod-.*"} |~ "(?i)(error|panic|fatal|exception)"

# Logs from a specific pod
{namespace="school-prod-blue", pod="auth-service-578786545f-xxxxx"}

# Filter by log level (if JSON logs)
{namespace="school-prod-blue"} | json | level="error"

# Count errors per service in last 5 min
sum by (container) (count_over_time({namespace="school-prod-blue"} |~ "(?i)error" [5m]))

# Rate of 5xx responses from nginx-style access logs
rate({container="frontend"} |~ "HTTP/.* 5.." [5m])
```

### Log retention

7 days on Loki's PVC (10Gi). For longer retention: either increase PVC size + retention, or ship to S3-compatible storage via Loki's boltdb-shipper (Phase 4+ work).

## Correlating logs + metrics

In Grafana, click a time range on any metric graph → right-click → **Logs for this selection** → jumps to Loki with the same time window + labels. Works the other way too.

Or manually: any Prometheus query's label set (`namespace`, `pod`, `container`) can be pasted into a Loki query `{namespace="X", pod="Y"}`.

## Alerts

### Where to view
`https://grafana.cybe.tech:8443/alerting/list` — all alert rules cluster-wide. Filter:
- Red = firing
- Yellow = pending
- Green = OK

### Where they fire to
Currently: nowhere. Alertmanager is deployed but has no notification receivers configured.

To wire Slack/email/PagerDuty: edit the Alertmanager config (via kube-prometheus-stack Helm values `alertmanager.config`). Not done in this session — tracked as a separate Phase 4 task.

## Debugging a prod incident — the playbook

### 1. "Is it actually broken?"
Check `School Domain Overview` dashboard → namespace = `school-prod-blue` (or whichever is live):
- **Pods Running count** should equal 16 (3×5 + 1 Neo4j)
- **Pod restarts (1h)** should be 0
- **PVC usage** should be green

### 2. "What broke?"
Open the **Alert rules** page, filter state=Firing. The alert name tells you.

### 3. "Why?"
Click through to the dashboard panel that shows the failing metric. Look at logs for the same time range:
- Panel → right-click → Logs for this selection
- Or Explore → Loki → `{namespace="school-prod-blue", container="auth-service"} | last 10 min`

### 4. "Is it still broken?"
Watch the metric return to normal. If alert clears on its own, it was transient. If not, you need to take action.

### 5. "Rollback?"
If the issue correlates with a recent deploy, git-revert the release on the gitops repo's main branch. Auto-promote pipeline catches this via its soak step but only within ~5 min of cutover.

For a longer-window incident: manually git-revert the last ~3 commits on main → bot pushes bumps → ArgoCD re-syncs → rolling deploy to previous version.

## What's NOT covered yet

- **Distributed tracing** (Jaeger/Tempo) — backlog
- **Real SLOs** — backlog, needs baseline traffic first
- **Alert channel integration** (Slack/PagerDuty) — P4 follow-up
- **Long-term log archive** (S3) — P4 follow-up
