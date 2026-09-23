# Hiren Beyond — AI-Powered Global Career & Recruitment Platform

Backend repository and database migrations for the **Hiren Beyond** enterprise recruitment ecosystem.

---

## Architecture Highlights

- **Database Engine**: Supabase PostgreSQL 17 (`eu-west-1`)
- **Project Ref**: `pthkmkwrqjyseonysjzu`
- **Security**: 100% database-enforced Row Level Security (RLS) across all entities
- **Access Control**: Granular Role-Based Access Control (RBAC) with 7 distinct system roles
- **Multi-Tenancy**: Tenant boundaries isolated via `organizations` and `organization_members`
- **Candidate Domain**: Comprehensive, normalized candidate model with dynamic profile completeness engine
- **Private Document Storage**: Secure Supabase Storage bucket (`candidate-documents`) governed by candidate-path RLS
- **Auditability**: Append-only, tamper-proof `audit_logs`
- **Authentication**: Seamless linkage with Supabase Auth (`auth.users`)

---

## Directory Structure

```text
Backend Project/
├── .env.example                               # Environment variable templates
├── README.md                                  # Project overview and instructions
├── docs/
│   ├── backend-foundation.md                  # Comprehensive architectural overview
│   ├── database-schema.md                     # Data dictionary, tables, types, and constraints
│   ├── roles-and-permissions.md               # RBAC matrix and capability token specifications
│   ├── security-and-rls.md                    # Detailed Row Level Security policies and audit
│   ├── supabase-setup.md                      # Setup guide, CLI instructions, and OAuth configuration
│   ├── verify-foundation.sql                  # Task 01 SQL validation script
│   ├── candidate-domain.md                    # Candidate Domain architectural reference
│   ├── candidate-security.md                  # Candidate security, RLS & anti-tampering rules
│   ├── candidate-documents.md                 # Candidate document storage & AI extraction readiness
│   └── verify-candidate-domain.sql            # Task 02 SQL validation script
└── supabase/
    ├── config.toml                            # Supabase CLI project configuration
    └── migrations/
        ├── 20260915000100_hiren_beyond_foundation.sql  # Core schemas, tables, triggers, and RLS
        ├── 20260915000200_hiren_beyond_seed.sql        # Seed roles, permissions, and platform org
        └── 20260915000300_candidate_domain.sql        # Complete Candidate Domain & Storage setup
```

---

## Quick Start

### 1. Prerequisites
- Node.js (v18+)
- Supabase CLI (via `npx -y supabase`)

### 2. Connect to Supabase
```bash
# Verify CLI
npx -y supabase --version

# Link repository to remote project
npx -y supabase link --project-ref pthkmkwrqjyseonysjzu
```

### 3. Apply Migrations
```bash
# Push migrations to the remote database
npx -y supabase db push --linked
```

### 4. Verify Database Integrity
```bash
# Validate Foundation (Task 01)
npx -y supabase db query --linked --file ./docs/verify-foundation.sql

# Validate Candidate Domain (Task 02)
npx -y supabase db query --linked --file ./docs/verify-candidate-domain.sql
```

---

## Documentation Links

### Foundation (Task 01)
- [Backend Architecture & Foundation](docs/backend-foundation.md)
- [Database Schema Reference](docs/database-schema.md)
- [Roles & Permissions (RBAC)](docs/roles-and-permissions.md)
- [Security & Row Level Security (RLS)](docs/security-and-rls.md)
- [Supabase Setup & Operations](docs/supabase-setup.md)

### Candidate Domain (Task 02)
- [Candidate Domain Architecture](docs/candidate-domain.md)
- [Candidate Security & Access Control](docs/candidate-security.md)
- [Candidate Documents & Storage](docs/candidate-documents.md)

---

## Next Planned Phase

**TASK 03 — Jobs Marketplace, Categories, Job Requirements, and Active Opportunities.**
