-- Supabase Auth/PostgREST policies. Laravel Sanctum tokens are not Supabase JWTs.
-- Store role, university_code, and is_super_admin in trusted app_metadata claims.

alter table public.certificates enable row level security;
alter table public.certificate_deletion_requests enable row level security;

grant select on public.certificates to authenticated;
grant insert, update, delete on public.certificates to authenticated;
grant select, insert, update on public.certificate_deletion_requests to authenticated;

create or replace function public.verify_certificate_hash(
    p_certificate_code text,
    p_sha256_hex text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
    select exists (
        select 1
        from public.certificates as certificate
        where certificate.certificate_code = p_certificate_code
          and pg_catalog.lower(certificate.cert_hash)
              = pg_catalog.lower(pg_catalog.replace(p_sha256_hex, '0x', ''))
          and pg_catalog.lower(certificate.status) in ('verified', 'valid')
    );
$function$;

revoke all on function public.verify_certificate_hash(text, text) from public;
grant execute on function public.verify_certificate_hash(text, text) to anon, authenticated;

drop policy if exists certificates_student_read_own on public.certificates;
create policy certificates_student_read_own
on public.certificates for select to authenticated
using (
    (
        pg_catalog.lower(coalesce(student_email, ''))
            = pg_catalog.lower(coalesce(auth.jwt() ->> 'email', ''))
        or pg_catalog.lower(coalesce(email, ''))
            = pg_catalog.lower(coalesce(auth.jwt() ->> 'email', ''))
    )
    and coalesce(auth.jwt() -> 'app_metadata' ->> 'role', 'student') in ('student', 'user')
);

drop policy if exists certificates_staff_read_school on public.certificates;
create policy certificates_staff_read_school
on public.certificates for select to authenticated
using (
    auth.jwt() -> 'app_metadata' ->> 'role' in ('registrar', 'admin')
    and (
        auth.jwt() -> 'app_metadata' ->> 'is_super_admin' = 'true'
        or university_code = auth.jwt() -> 'app_metadata' ->> 'university_code'
    )
);

drop policy if exists certificates_staff_insert_school on public.certificates;
create policy certificates_staff_insert_school
on public.certificates for insert to authenticated
with check (
    auth.jwt() -> 'app_metadata' ->> 'role' in ('registrar', 'admin')
    and (
        auth.jwt() -> 'app_metadata' ->> 'is_super_admin' = 'true'
        or university_code = auth.jwt() -> 'app_metadata' ->> 'university_code'
    )
);

drop policy if exists certificates_staff_update_school on public.certificates;
create policy certificates_staff_update_school
on public.certificates for update to authenticated
using (
    auth.jwt() -> 'app_metadata' ->> 'role' in ('registrar', 'admin')
    and (
        auth.jwt() -> 'app_metadata' ->> 'is_super_admin' = 'true'
        or university_code = auth.jwt() -> 'app_metadata' ->> 'university_code'
    )
)
with check (
    auth.jwt() -> 'app_metadata' ->> 'role' in ('registrar', 'admin')
    and (
        auth.jwt() -> 'app_metadata' ->> 'is_super_admin' = 'true'
        or university_code = auth.jwt() -> 'app_metadata' ->> 'university_code'
    )
);

drop policy if exists certificates_staff_delete_school on public.certificates;
create policy certificates_staff_delete_school
on public.certificates for delete to authenticated
using (
    auth.jwt() -> 'app_metadata' ->> 'role' in ('registrar', 'admin')
    and (
        auth.jwt() -> 'app_metadata' ->> 'is_super_admin' = 'true'
        or university_code = auth.jwt() -> 'app_metadata' ->> 'university_code'
    )
);

-- These UUID columns bridge Supabase Auth users to the existing Laravel integer user IDs.
alter table public.certificate_deletion_requests
    add column if not exists requested_by_auth_id uuid references auth.users(id) on delete set null,
    add column if not exists reviewed_by_auth_id uuid references auth.users(id) on delete set null;

drop policy if exists deletion_requests_staff_read_school on public.certificate_deletion_requests;
create policy deletion_requests_staff_read_school
on public.certificate_deletion_requests for select to authenticated
using (
    auth.jwt() -> 'app_metadata' ->> 'role' in ('registrar', 'admin')
    and (
        auth.jwt() -> 'app_metadata' ->> 'is_super_admin' = 'true'
        or university_code = auth.jwt() -> 'app_metadata' ->> 'university_code'
    )
);

drop policy if exists deletion_requests_staff_insert_school on public.certificate_deletion_requests;
create policy deletion_requests_staff_insert_school
on public.certificate_deletion_requests for insert to authenticated
with check (
    requested_by_auth_id = auth.uid()
    and status = 'pending'
    and auth.jwt() -> 'app_metadata' ->> 'role' in ('registrar', 'admin')
    and (
        auth.jwt() -> 'app_metadata' ->> 'is_super_admin' = 'true'
        or university_code = auth.jwt() -> 'app_metadata' ->> 'university_code'
    )
);

drop policy if exists deletion_requests_staff_review_school on public.certificate_deletion_requests;
create policy deletion_requests_staff_review_school
on public.certificate_deletion_requests for update to authenticated
using (
    auth.jwt() -> 'app_metadata' ->> 'role' in ('registrar', 'admin')
    and status = 'pending'
    and (
        auth.jwt() -> 'app_metadata' ->> 'is_super_admin' = 'true'
        or university_code = auth.jwt() -> 'app_metadata' ->> 'university_code'
    )
)
with check (
    auth.jwt() -> 'app_metadata' ->> 'role' in ('registrar', 'admin')
    and reviewed_by_auth_id = auth.uid()
    and status in ('approved', 'rejected')
    and (
        auth.jwt() -> 'app_metadata' ->> 'is_super_admin' = 'true'
        or university_code = auth.jwt() -> 'app_metadata' ->> 'university_code'
    )
);