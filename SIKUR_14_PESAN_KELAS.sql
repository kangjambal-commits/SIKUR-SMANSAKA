-- SIKUR_14_PESAN_KELAS.sql
-- Pesan/pengumuman yang ditujukan kepada satu, beberapa, atau seluruh kelas.
-- Pesan dibaca oleh ketua kelas melalui PantauKBM menggunakan token sesi.

create table if not exists public.sikur_pesan_kelas (
  id uuid primary key default gen_random_uuid(),
  judul text not null check (char_length(btrim(judul)) between 1 and 120),
  isi text not null check (char_length(btrim(isi)) between 1 and 3000),
  kelas text[] not null check (cardinality(kelas) between 1 and 27),
  prioritas text not null default 'biasa' check (prioritas in ('biasa','penting')),
  aktif boolean not null default true,
  mulai_tampil date not null default (timezone('Asia/Jakarta', now()))::date,
  berlaku_sampai date,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint sikur_pesan_kelas_valid_dates
    check (berlaku_sampai is null or berlaku_sampai >= mulai_tampil)
);

create index if not exists idx_sikur_pesan_kelas_targets
  on public.sikur_pesan_kelas using gin(kelas);
create index if not exists idx_sikur_pesan_kelas_active_dates
  on public.sikur_pesan_kelas(aktif, mulai_tampil, berlaku_sampai);

alter table public.sikur_pesan_kelas enable row level security;
revoke all on table public.sikur_pesan_kelas from public, anon, authenticated;
grant select, insert, update, delete on table public.sikur_pesan_kelas to authenticated;

drop policy if exists read_pesan_kelas on public.sikur_pesan_kelas;
create policy read_pesan_kelas
  on public.sikur_pesan_kelas for select to authenticated
  using (true);

drop policy if exists manage_pesan_kelas on public.sikur_pesan_kelas;
create policy manage_pesan_kelas
  on public.sikur_pesan_kelas for all to authenticated
  using (public.sikur_my_role() = any (array['admin','waka']::text[]))
  with check (public.sikur_my_role() = any (array['admin','waka']::text[]));

create or replace function public.sikur_pesan_kelas_hari_ini(p_token text)
returns table(
  id uuid,
  judul text,
  isi text,
  prioritas text,
  mulai_tampil date,
  berlaku_sampai date,
  created_at timestamptz
)
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $function$
declare
  v_ketua public.sikur_ketua_kelas%rowtype;
  v_tanggal date := (timezone('Asia/Jakarta', now()))::date;
begin
  select k.* into v_ketua
  from public.sikur_ketua_kelas_sesi s
  join public.sikur_ketua_kelas k on k.id = s.ketua_id
  where s.berlaku_sampai > now()
    and extensions.crypt(p_token,s.token_hash) = s.token_hash
    and k.aktif = true
  order by s.id desc limit 1;

  if not found then
    raise exception 'Sesi PantauKBM tidak valid atau sudah berakhir';
  end if;

  return query
  select p.id,p.judul,p.isi,p.prioritas,p.mulai_tampil,p.berlaku_sampai,p.created_at
  from public.sikur_pesan_kelas p
  where p.aktif = true
    and p.kelas @> array[v_ketua.kelas]::text[]
    and p.mulai_tampil <= v_tanggal
    and (p.berlaku_sampai is null or p.berlaku_sampai >= v_tanggal)
  order by case when p.prioritas='penting' then 0 else 1 end, p.created_at desc;
end;
$function$;

revoke all on function public.sikur_pesan_kelas_hari_ini(text) from public;
grant execute on function public.sikur_pesan_kelas_hari_ini(text) to anon, authenticated;

do $$
begin
  if exists (select 1 from pg_publication where pubname='supabase_realtime')
     and not exists (
       select 1 from pg_publication_tables
       where pubname='supabase_realtime'
         and schemaname='public'
         and tablename='sikur_pesan_kelas'
     ) then
    execute 'alter publication supabase_realtime add table public.sikur_pesan_kelas';
  end if;
end
$$;
