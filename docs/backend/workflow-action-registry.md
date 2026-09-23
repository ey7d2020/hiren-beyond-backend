# Workflow Action Registry

Every supported workflow action type with full specification.

---

## send_notification
- **Description:** Emit a notification event via Task 11 infrastructure
- **Required Permission:** `workflows.execute`
- **Risk Level:** low
- **Requires Approval:** No
- **Input Schema:** `{notification_type: string, recipient_id?: uuid}`
- **Output Schema:** `{action: 'notification_emitted', type: string}`
- **Side Effects:** Inserts into `notification_events` via `emit_notification_event()`
- **Idempotency:** emit_notification_event handles dedup per preference

---

## move_application_stage
- **Description:** Move an application to a specific ATS stage
- **Required Permission:** `workflows.execute` + org membership
- **Risk Level:** medium
- **Requires Approval:** Configurable
- **Input Schema:** `{stage_id: uuid}`
- **Output Schema:** `{action: 'stage_moved', stage_id: uuid}`
- **Side Effects:** UPDATE applications.current_stage_id → ATS trigger fires application_events, application_stage_history
- **Idempotency:** Moving to already-current stage is a no-op (no rows updated)

---

## shortlist_candidate
- **Description:** Mark application as shortlisted and add to review queue
- **Required Permission:** `workflows.execute`
- **Risk Level:** medium
- **Requires Approval:** No
- **Input Schema:** `{reason?: string, priority?: string}`
- **Output Schema:** `{action: 'candidate_shortlisted'}`
- **Side Effects:** UPDATE applications.status, INSERT recruiter_review_queue
- **Idempotency:** Duplicate shortlist status update is idempotent

---

## reject_application
- **Description:** Reject an application (sets status to rejected)
- **Required Permission:** `workflows.execute` + `workflows.approve` for auto-rejection
- **Risk Level:** high
- **Requires Approval:** YES (configurable)
- **Input Schema:** `{reason?: string}`
- **Output Schema:** `{action: 'application_rejected'}`
- **Side Effects:** UPDATE applications.status = 'rejected'
- **Idempotency:** Rejecting an already-rejected application is a no-op

---

## create_assessment_invitation
- **Description:** Trigger required assessments for an application
- **Required Permission:** `workflows.execute`
- **Risk Level:** medium
- **Requires Approval:** No
- **Input Schema:** `{}` (uses application_id as entity)
- **Output Schema:** `{action: 'assessments_triggered'}`
- **Side Effects:** Calls `trigger_required_assessments()` which creates assessment_invitations
- **Idempotency:** `trigger_required_assessments` skips existing invitations

---

## add_to_talent_pool
- **Description:** Add candidate to a talent pool
- **Required Permission:** `workflows.execute`
- **Risk Level:** low
- **Requires Approval:** No
- **Input Schema:** `{talent_pool_id: uuid, source?: string, notes?: string}`
- **Output Schema:** `{action: 'added_to_talent_pool', pool_id: uuid}`
- **Side Effects:** Calls `add_candidate_to_talent_pool()` → inserts talent_pool_members
- **Idempotency:** Pool membership has unique constraint; duplicate add is no-op

---

## remove_from_talent_pool
- **Description:** Remove candidate from a talent pool
- **Required Permission:** `workflows.execute`
- **Risk Level:** low
- **Requires Approval:** No
- **Input Schema:** `{talent_pool_id: uuid}`
- **Output Schema:** `{action: 'removed_from_talent_pool'}`
- **Side Effects:** Sets talent_pool_members.status = 'removed'
- **Idempotency:** Removing already-removed member is a no-op

---

## create_review_item
- **Description:** Add candidate to recruiter review queue
- **Required Permission:** `workflows.execute`
- **Risk Level:** low
- **Requires Approval:** No
- **Input Schema:** `{reason?: string, priority?: low|medium|high|urgent}`
- **Output Schema:** `{action: 'review_item_created'}`
- **Side Effects:** INSERT into recruiter_review_queue
- **Idempotency:** Creates a new review item (not deduped by default)

---

## run_matching
- **Description:** Enqueue a matching computation for an application
- **Required Permission:** `workflows.execute`
- **Risk Level:** medium
- **Requires Approval:** No
- **Input Schema:** `{job_id: uuid}`
- **Output Schema:** `{action: 'matching_enqueued'}`
- **Side Effects:** `enqueue_workflow_event('matching_requested', ...)` — async
- **Idempotency:** Idempotency key prevents duplicate matching events

---

## create_analytics_event
- **Description:** Log a workflow analytics event to audit_logs
- **Required Permission:** `workflows.execute`
- **Risk Level:** read
- **Requires Approval:** No
- **Input Schema:** `{event_name?: string, ...metadata}`
- **Output Schema:** `{action: 'analytics_event_created'}`
- **Side Effects:** INSERT into audit_logs with workflow metadata
- **Idempotency:** Each call creates a new audit entry

---

## call_webhook
- **Description:** Call an approved external webhook endpoint
- **Required Permission:** `workflows.execute` + pre-registered integration
- **Risk Level:** medium
- **Requires Approval:** Configurable
- **Input Schema:** `{integration_id: uuid, payload?: object}`
- **Output Schema:** `{action: 'call_webhook', status: 'logged'}`
- **Side Effects:** Logs to workflow_execution_logs; actual HTTP call by external worker
- **Idempotency:** Webhook retry policy applies

---

## start_ai_action
- **Description:** Trigger an AI action via Task 12 AI action layer
- **Required Permission:** `workflows.execute` + underlying AI permission
- **Risk Level:** medium
- **Requires Approval:** Configurable
- **Input Schema:** `{action_type: string, tool_id?: uuid}`
- **Output Schema:** `{action: 'start_ai_action', status: 'logged'}`
- **Side Effects:** Logs; actual AI invocation by external worker via ai_action_requests
- **Idempotency:** Tool call dedup via ai_tool_calls table

---

## send_billing_notification
- **Description:** Send a billing-related notification to org admin
- **Required Permission:** `workflows.execute`
- **Risk Level:** medium
- **Requires Approval:** No
- **Input Schema:** `{notification_type: string}`
- **Output Schema:** `{action: 'send_billing_notification', status: 'logged'}`
- **Side Effects:** Logs; actual notification via Task 11
- **Idempotency:** Notification dedup via preferences system

---

## restrict_feature / restore_feature
- **Description:** Restrict or restore a feature for an organization
- **Required Permission:** `workflows.admin`
- **Risk Level:** high
- **Requires Approval:** YES
- **Input Schema:** `{feature_key: string}`
- **Output Schema:** `{action: 'restrict_feature'|'restore_feature', status: 'logged'}`
- **Side Effects:** Uses Task 14 subscription logic (not direct payment changes)
- **Idempotency:** Feature flag update is idempotent

