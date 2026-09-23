# External Integration Permission Scopes & Privacy Specification

This document details the minimal OAuth permission scopes and provider access tiers required by the **Hiren Beyond** external integration engine. In compliance with enterprise security, Google API Services User Data Policy, Meta Business Policies, and Microsoft Graph requirements, only strictly necessary functional scopes are requested.

---

## OAuth & Provider Scope Catalog

| Provider | Scope Key | Classification | Business Purpose | Data Accessed |
|---|---|---|---|---|
| **Google Calendar** | `https://www.googleapis.com/auth/calendar.events` | Sensitive | Bi-directional interview scheduling, event creation, rescheduling, and cancellation | Calendar events created by Hiren Beyond for recruiter/candidate interviews. Does not access personal contacts, emails, or unrelated calendar titles. |
| **Google Calendar** | `https://www.googleapis.com/auth/calendar.readonly` | Sensitive | Free/Busy conflict detection during interview slot proposing | Recruiter busy/free time blocks without reading event summaries or attendee details. |
| **Google Meet** | `https://www.googleapis.com/auth/calendar.events` | Sensitive | Automatic generation of video meeting URLs (`hangoutsMeet`) tied to scheduled interview rounds | Meeting ID and join URL generation. |
| **Microsoft Calendar** | `Calendars.ReadWrite` | Sensitive | Office 365 / Outlook calendar synchronization for enterprise recruiters | Scheduling and updating interview appointments in the recruiter's work calendar. |
| **Microsoft Calendar** | `Calendars.Read` | Sensitive | Free/Busy availability lookups across Outlook calendar slots | Free/Busy availability slots. |
| **WhatsApp Business** | `whatsapp_business_messaging` | Sensitive | Candidate status alerts, interview reminders, assessment links, and urgent notifications | Recipient phone number, registered template name, and authorized template variable parameters. No personal contact list harvesting. |
| **Google Sheets** | `https://www.googleapis.com/auth/spreadsheets` | Sensitive | Asynchronous export of candidate summaries, job pipeline data, and recruitment analytics | Dedicated target spreadsheets created or selected by the recruiter. System never scans or accesses unmapped spreadsheets in Google Drive. |
| **Outbound Webhooks** | `hmac_sha256_signed` | Non-OAuth | Real-time event notifications to customer ATS, HRIS, or external workflow engines | Specific subscribed event payload (e.g. `candidate_interview_confirmed`, `candidate_hired`). Signed with SHA256 HMAC. |
| **Custom REST API** | `bearer` / `api_key` | Non-OAuth | Custom enterprise ERP/CRM webhook integration | Tenant-configured request payloads. |

---

## Privacy & Security Invariants

1. **Least-Privilege Enforcement**: Scopes like `https://www.googleapis.com/auth/calendar` (full account access) or `https://www.googleapis.com/auth/drive` (full file access) are strictly prohibited. The system only requests `.events` and `.spreadsheets`.
2. **Zero Plaintext Storage**: Access tokens, refresh tokens, and client secrets are never stored in standard relational table columns. They are stored in secure server-side key vaults (Supabase Vault / KMS), referenced only by opaque pointers (`credential_reference`).
3. **No Private Recruiter Notes Export**: Google Sheets exports automatically strip internal recruiter evaluation notes, interview scoring rubrics, and private candidate comments unless explicitly authorized by an organization admin.
4. **Scope Verification on Callback**: The `complete_oauth_session` RPC function validates that the external provider granted all requested scopes. If a user unchecks a required scope during consent, the connection is rejected before activation.
