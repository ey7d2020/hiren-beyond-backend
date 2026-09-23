# Frontend Integration Examples

These examples use implemented local migrations where possible. Replace table field names with generated `Database` types after remote verification.

## Supabase Client

```ts
import { createClient } from '@supabase/supabase-js';
import type { Database } from '../../types/database.types';

export const supabase = createClient<Database>(
  import.meta.env.VITE_SUPABASE_URL,
  import.meta.env.VITE_SUPABASE_ANON_KEY,
  {
    auth: {
      persistSession: true,
      autoRefreshToken: true,
      detectSessionInUrl: true,
    },
  },
);
```

## Resolve Current User Context

```ts
export async function loadUserContext() {
  const { data: sessionResult } = await supabase.auth.getSession();
  if (!sessionResult.session) return { state: 'unauthenticated' as const };

  const profile = await supabase.rpc('get_my_profile').single();
  if (profile.error) throw profile.error;

  const orgs = await supabase.rpc('get_user_organizations');
  if (orgs.error) throw orgs.error;
  if (!orgs.data?.length) return { state: 'authenticated_no_org' as const, profile: profile.data };

  const activeOrg = orgs.data[0];
  const permissions = await supabase.rpc('get_user_permissions', {
    p_organization_id: activeOrg.organization_id,
  });
  if (permissions.error) throw permissions.error;

  return { state: 'ready' as const, profile: profile.data, activeOrg, permissions: permissions.data ?? [] };
}
```

## Candidate CV Upload

Status: implemented primitives; no upload-session RPC exists in this repo.

```ts
export async function uploadCandidateDocument(candidateId: string, file: File) {
  const allowed = [
    'application/pdf',
    'application/msword',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'image/jpeg',
    'image/png',
  ];
  if (!allowed.includes(file.type)) throw new Error('UNSUPPORTED_FILE_TYPE');
  if (file.size > 20 * 1024 * 1024) throw new Error('FILE_TOO_LARGE');

  const objectPath = `${candidateId}/${crypto.randomUUID()}-${file.name}`;
  const upload = await supabase.storage.from('candidate-documents').upload(objectPath, file);
  if (upload.error) throw upload.error;

  const inserted = await supabase
    .from('candidate_documents')
    .insert({
      candidate_id: candidateId,
      storage_path: objectPath,
      file_name: file.name,
      mime_type: file.type,
      file_size_bytes: file.size,
    })
    .select('id')
    .single();
  if (inserted.error) throw inserted.error;

  const queued = await supabase.rpc('queue_cv_processing', {
    p_candidate_document_id: inserted.data.id,
  });
  if (queued.error) throw queued.error;

  return inserted.data.id;
}
```

## Poll CV Processing

```ts
export async function pollCvProcessing(documentId: string, signal?: AbortSignal) {
  while (!signal?.aborted) {
    const { data, error } = await supabase.rpc('get_cv_processing_status', {
      p_candidate_document_id: documentId,
    });
    if (error) throw error;

    const status = data?.[0]?.status;
    if (['completed', 'failed', 'review_required'].includes(status)) return data?.[0];

    await new Promise((resolve) => setTimeout(resolve, 4000));
  }
}
```

## Recruiter Searches Candidates

```ts
export async function searchCandidates(query: string, skills: string[], page = 1) {
  const { data, error } = await supabase.rpc('search_candidates', {
    p_query_text: query || null,
    p_skills: skills.length ? skills : null,
    p_page: page,
    p_page_size: 20,
    p_sort_by: 'relevance',
  });
  if (error) throw error;
  return data ?? [];
}
```

## Application Pipeline Move

```ts
export async function moveApplication(applicationId: string, stageId: string, note?: string) {
  const { data, error } = await supabase.rpc('advance_application_stage', {
    p_application_id: applicationId,
    p_new_stage_id: stageId,
    p_notes: note ?? null,
  });
  if (error) throw error;
  return data;
}
```

After the move, refetch the pipeline board. Do not silently overwrite newer stage state.

## Client Candidate Review

```ts
export async function submitClientDecision(shareId: string, decision: string, comments?: string) {
  const { data, error } = await supabase.rpc('submit_client_feedback', {
    p_share_id: shareId,
    p_decision: decision,
    p_comments: comments ?? null,
  });
  if (error) throw error;
  return data;
}
```

## Notification Center

```ts
export async function listUnreadNotifications(cursor?: string) {
  const { data, error } = await supabase.rpc('list_notifications', {
    p_limit: 20,
    p_cursor: cursor ?? null,
    p_unread_only: true,
  });
  if (error) throw error;

  return {
    items: data ?? [],
    hasMore: Boolean(data?.[0]?.has_more),
    nextCursor: data?.[0]?.next_cursor ?? null,
  };
}
```

## Public API Key Creation

This is for a developer portal used by organization admins. The generated key is shown once.

```ts
export async function createApiKey(applicationId: string) {
  const { data, error } = await supabase.rpc('create_api_key', {
    p_application_id: applicationId,
    p_name: 'Production server',
    p_scopes: ['jobs.read', 'applications.read'],
    p_expires_in_days: 365,
  });
  if (error) throw error;
  return data;
}
```

