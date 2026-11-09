-- SIKUR_13_JADWAL_KHUSUS.sql
-- Jadwal Khusus Sekolah: perubahan waktu KBM pada tanggal tertentu.
-- Berlaku seragam untuk semua kelas dan tidak mengubah jadwal reguler.
-- Jalankan pada proyek Supabase SIKUR-SMANSAKA setelah SIKUR_12.

create table if not exists public.sikur_jadwal_khusus (
  tanggal date primary key,
  nama_kegiatan text not null
    check (char_length(btrim(nama_kegiatan)) between 1 and 120),
  keterangan text,
  waktu jsonb not null
    check (
      jsonb_typeof(waktu) = 'array'
      and jsonb_array_length(waktu) between 1 and 10
    ),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_sikur_jadwal_khusus_created_by
  on public.sikur_jadwal_khusus(created_by);

alter table public.sikur_jadwal_khusus enable row level security;
revoke all on table public.sikur_jadwal_khusus from public, anon, authenticated;
grant select, insert, update, delete on table public.sikur_jadwal_khusus to authenticated;

drop policy if exists read_jadwal_khusus on public.sikur_jadwal_khusus;
create policy read_jadwal_khusus
  on public.sikur_jadwal_khusus
  for select to authenticated
  using (true);

drop policy if exists manage_jadwal_khusus on public.sikur_jadwal_khusus;
create policy manage_jadwal_khusus
  on public.sikur_jadwal_khusus
  for all to authenticated
  using (public.sikur_my_role() = any (array['admin','waka']::text[]))
  with check (public.sikur_my_role() = any (array['admin','waka']::text[]));

-- Waktu dan JP aktif pada PantauKBM mengikuti override khusus tanggal berjalan.
create or replace function public.sikur_jadwal_ketua_hari_ini(p_token text)
returns table(
  jadwal_id bigint,
  hari text,
  jam_ke integer,
  kelas text,
  kode_guru text,
  nama_guru text,
  kode_mapel text,
  nama_mapel text,
  mulai time without time zone,
  selesai time without time zone,
  status_laporan text,
  jam_masuk time without time zone,
  jam_keluar time without time zone,
  keterangan text
)
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $function$
declare
  v_ketua public.sikur_ketua_kelas%rowtype;
  v_tanggal date := (timezone('Asia/Jakarta', now()))::date;
  v_hari text;
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

  v_hari := case extract(isodow from v_tanggal)
    when 1 then 'Senin'
    when 2 then 'Selasa'
    when 3 then 'Rabu'
    when 4 then 'Kamis'
    when 5 then 'Jumat'
    when 6 then 'Sabtu'
    else 'Minggu'
  end;

  return query
  select
    j.id::bigint,
    j.hari::text,
    j.jam_ke::integer,
    j.kelas::text,
    j.kode_guru::text,
    g.nama_guru::text,
    j.kode_mapel::text,
    m.nama_mapel::text,
    coalesce(nullif(khusus.mulai,'')::time,kb.mulai::time),
    coalesce(nullif(khusus.selesai,'')::time,kb.selesai::time),
    mon.status_laporan::text,
    mon.jam_masuk::time,
    mon.jam_keluar::time,
    mon.keterangan::text
  from public.sikur_jadwal j
  join public.sikur_guru g on g.kode_guru=j.kode_guru
  join public.sikur_mapel m on m.kode_mapel=j.kode_mapel
  left join public.sikur_jam_kbm kb
    on kb.hari=j.hari and kb.jam_ke=j.jam_ke
  left join lateral (
    select
      slot.value->>'aktif' as aktif,
      slot.value->>'mulai' as mulai,
      slot.value->>'selesai' as selesai
    from public.sikur_jadwal_khusus sk
    cross join lateral jsonb_array_elements(sk.waktu) as slot(value)
    where sk.tanggal=v_tanggal
      and (slot.value->>'jam_ke')::integer=j.jam_ke
    limit 1
  ) khusus on true
  left join public.sikur_monitoring_kbm mon
    on mon.tanggal=v_tanggal
    and mon.kelas=j.kelas
    and mon.jadwal_id=j.id
  where j.kelas=v_ketua.kelas
    and j.hari=v_hari
    and coalesce(nullif(khusus.aktif,'')::boolean,true)
  order by j.jam_ke;
end;
$function$;

revoke all on function public.sikur_jadwal_ketua_hari_ini(text) from public;
grant execute on function public.sikur_jadwal_ketua_hari_ini(text) to anon, authenticated;

-- Aktifkan publikasi realtime untuk sinkronisasi ant perangkat.
do $$
begin
  if exists (
    select 1 from pg_publication where pubname='supabase_realtime'
  ) and not exists (
    select 1
    from pg_publication_tables
    where pubname='supabase_realtime'
      and schemaname='public'
      and tablename='sikur_jadwal_khusus'
  ) then
    execute 'alter publication supabase_realtime add table public.sikur_jadwal_khusus';
  end if;
end
$$;
