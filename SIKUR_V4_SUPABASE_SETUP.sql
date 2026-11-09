-- SIKUR v4 Cloud - jalankan di Supabase SQL Editor
create table if not exists public.sikur_state (
  id text primary key,
  data jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

alter table public.sikur_state enable row level security;

drop policy if exists "SIKUR authenticated read" on public.sikur_state;
create policy "SIKUR authenticated read"
on public.sikur_state for select
to authenticated
using (
  exists (
    select 1 from public.sikur_profiles p
    where p.id = auth.uid()
      and p.role in ('admin','waka','kepala','guru')
  )
);

drop policy if exists "SIKUR authenticated insert" on public.sikur_state;
create policy "SIKUR authenticated insert"
on public.sikur_state for insert
to authenticated
with check (
  exists (
    select 1 from public.sikur_profiles p
    where p.id = auth.uid()
      and p.role in ('admin','waka')
  )
);

drop policy if exists "SIKUR authenticated update" on public.sikur_state;
create policy "SIKUR authenticated update"
on public.sikur_state for update
to authenticated
using (
  exists (
    select 1 from public.sikur_profiles p
    where p.id = auth.uid()
      and p.role in ('admin','waka')
  )
)
with check (
  exists (
    select 1 from public.sikur_profiles p
    where p.id = auth.uid()
      and p.role in ('admin','waka')
  )
);
