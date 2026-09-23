# Hiren Beyond — Backup & Disaster Recovery (DR) Plan

## 1. Service Level Objectives

| Metric | Target | Description |
|--------|--------|-------------|
| **RPO** (Recovery Point Objective) | **< 15 Minutes** | Maximum data loss tolerated during disaster scenario |
| **RTO** (Recovery Time Objective) | **< 60 Minutes** | Maximum tolerable platform downtime until service restoration |

---

## 2. Supabase Automated Backup Architecture
- **Continuous Write-Ahead Logging (WAL)**: Supabase archives continuous WAL files enabling Point-in-Time Recovery (PITR) down to the exact second.
- **Daily Physical Snapshots**: Full base backups taken daily at 00:00 UTC with 7-day to 30-day retention depending on tier.
- **Geographic Replication**: Backups stored in geo-redundant object storage isolated from primary compute infrastructure.

---

## 3. Disaster Scenarios & Recovery Runbooks

### Scenario A: Accidental Bad Migration / Schema Corruption
1. **Isolate**: Set maintenance mode via platform announcements banner.
2. **Identify Target Timestamp**: Find timestamp immediately preceding bad migration in `audit_logs` or `supabase_migrations`.
3. **Execute PITR**:
   - In Supabase Dashboard -> Project Settings -> Database -> Backups -> Point-in-Time Recovery.
   - Select timestamp: `T_incident - 2 minutes`.
   - Restore into a clone project or restore in place.
4. **Verification**: Run `docs/production/test-production-hardening.sql` to verify database health.

### Scenario B: Catastrophic Primary Host Outage (Region Failure)
1. **Notify Incident Commander**: Alert engineering on-call via PagerDuty.
2. **Provision Standby Project**: Initialize backup Supabase project in secondary AWS/GCP region.
3. **Restore from Latest WAL Snapshot**: Restore latest PITR snapshot into secondary project.
4. **DNS Failover**: Update Cloudflare / Route53 DNS CNAME records for API gateway and frontend domains.
5. **Re-sync Secrets & Webhooks**: Verify Stripe, WhatsApp, SendGrid, and AI provider webhook endpoints point to secondary region.

---

## 4. Verification Schedule
- **Weekly Automated Backup Verification**: Automated health probe confirms WAL archiving health.
- **Quarterly Table-Top DR Drill**: Simulates cold-standby restoration in staging environment to measure actual RTO/RPO.
