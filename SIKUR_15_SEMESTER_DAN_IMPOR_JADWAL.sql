-- SIKUR_15_SEMESTER_DAN_IMPOR_JADWAL.sql
-- Periode semester dan impor jadwal secara transaksional.
-- Jadwal periode lama tidak dihapus agar relasi laporan PantauKBM tetap utuh.

create table if not exists public.sikur_periode_semester (
  id uuid primary key default gen_random_uuid(),
  tahun_ajaran text not null check (tahun_ajaran ~ '^[0-9]{4}/[0-9]{4}$'),
  semester text not null check (semester in ('Ganjil','Genap')),
  versi integer not null check (versi >= 1),
  aktif boolean not null default false,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint sikur_periode_semester_version_unique unique (tahun_ajaran, semester, versi)
);

-- Migrasi pertama mempertahankan jadwal produksi yang sedang berjalan sebagai
-- arsip Semester Ganjil TA 2026/2027.
do $$
declare
  v_period_id uuid;
begin
  select id into v_period_id
  from public.sikur_periode_semester
  where aktif=true
  order by created_at desc
  limit 1;

  if v_period_id is null then
    insert into public.sikur_periode_semester(tahun_ajaran,semester,versi,aktif)
    values ('2026/2027','Ganjil',1,true)
    on conflict (tahun_ajaran,semester,versi) do update set aktif=true
    returning id into v_period_id;
  end if;

  alter table public.sikur_jadwal add column if not exists periode_id uuid;
  update public.sikur_jadwal set periode_id=v_period_id where periode_id is null;
end
$$;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid='public.sikur_jadwal'::regclass
      and conname='sikur_jadwal_periode_id_fkey'
  ) then
    alter table public.sikur_jadwal
      add constraint sikur_jadwal_periode_id_fkey
      foreign key (periode_id) references public.sikur_periode_semester(id);
  end if;
end
$$;

alter table public.sikur_jadwal alter column periode_id set not null;

create index if not exists idx_sikur_jadwal_periode_id
  on public.sikur_jadwal(periode_id);
create unique index if not exists uq_sikur_jadwal_periode_slot_kelas
  on public.sikur_jadwal(periode_id,hari,jam_ke,kelas);

create sequence if not exists public.sikur_jadwal_id_seq;
select setval(
  'public.sikur_jadwal_id_seq',
  greatest(coalesce((select max(id) from public.sikur_jadwal),0),1),
  coalesce((select max(id) from public.sikur_jadwal),0)>0
);
alter table public.sikur_jadwal
  alter column id set default nextval('public.sikur_jadwal_id_seq');

create unique index if not exists uq_sikur_one_active_semester
  on public.sikur_periode_semester(aktif)
  where aktif=true;

alter table public.sikur_periode_semester enable row level security;
revoke all on table public.sikur_periode_semester from public, anon, authenticated;
grant select on table public.sikur_periode_semester to authenticated;

drop policy if exists read_sikur_periode_semester on public.sikur_periode_semester;
create policy read_sikur_periode_semester
  on public.sikur_periode_semester for select to authenticated
  using (true);

-- Seluruh pengguna terautentikasi hanya membaca daftar periode.
-- Perubahan periode/jadwal hanya melalui RPC SECURITY DEFINER yang memeriksa role.

create or replace function public.sikur_import_semester_schedule(
  p_tahun_ajaran text,
  p_semester text,
  p_rows jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_user uuid := auth.uid();
  v_count integer;
  v_classes integer;
  v_version integer;
  v_period_id uuid;
begin
  if v_user is null or public.sikur_my_role() not in ('admin','waka') then
    raise exception 'Hanya Admin/Waka Kurikulum yang dapat mengganti jadwal semester';
  end if;

  if p_tahun_ajaran is null or p_tahun_ajaran !~ '^[0-9]{4}/[0-9]{4}$' then
    raise exception 'Tahun ajaran harus menggunakan format YYYY/YYYY';
  end if;
  if p_semester not in ('Ganjil','Genap') then
    raise exception 'Semester harus Ganjil atau Genap';
  end if;
  if p_rows is null or jsonb_typeof(p_rows) <> 'array'
     or jsonb_array_length(p_rows) < 1
     or jsonb_array_length(p_rows) > 4000 then
    raise exception 'File harus berisi 1 sampai 4000 baris jadwal';
  end if;

  perform pg_advisory_xact_lock(hashtext('sikur_semester_switch'));

  drop table if exists pg_temp.sikur_import_rows;
  create temporary table sikur_import_rows on commit drop as
  select
    nullif(btrim(x.hari),'') as hari,
    x.jam_ke,
    nullif(btrim(x.kelas),'') as kelas,
    nullif(btrim(x.kode_mapel),'') as kode_mapel,
    nullif(btrim(x.kode_guru),'') as kode_guru
  from jsonb_to_recordset(p_rows) as x(
    hari text,
    jam_ke integer,
    kelas text,
    kode_mapel text,
    kode_guru text
  );

  select count(*) into v_count from pg_temp.sikur_import_rows;
  if v_count < 1 then raise exception 'Tidak ada baris jadwal yang dapat diproses'; end if;

  if exists (
    select 1 from pg_temp.sikur_import_rows
    where hari is null or jam_ke is null or kelas is null
       or kode_mapel is null or kode_guru is null
  ) then
    raise exception 'Ada baris yang belum lengkap (Hari, JP, Kelas, Kode Mapel, atau Kode Guru)';
  end if;

  if exists (
    select 1 from pg_temp.sikur_import_rows r
    where not exists (select 1 from public.sikur_jam_kbm j where j.hari=r.hari and j.jam_ke=r.jam_ke)
  ) then
    raise exception 'Ada kombinasi hari dan JP yang tidak tersedia pada pengaturan jam KBM';
  end if;

  if exists (
    select 1 from pg_temp.sikur_import_rows r
    where not exists (select 1 from public.sikur_kelas k where k.kelas=r.kelas)
       or not exists (select 1 from public.sikur_mapel m where m.kode_mapel=r.kode_mapel)
       or not exists (select 1 from public.sikur_guru g where g.kode_guru=r.kode_guru)
  ) then
    raise exception 'Ada kode kelas, mata pelajaran, atau guru yang tidak ditemukan pada Data Master';
  end if;

  if exists (
    select 1 from pg_temp.sikur_import_rows
    group by hari,jam_ke,kelas having count(*)>1
  ) then
    raise exception 'Bentrok: satu kelas memiliki lebih dari satu pelajaran pada hari dan JP yang sama';
  end if;

  if exists (
    select 1 from pg_temp.sikur_import_rows
    group by hari,jam_ke,kode_guru having count(distinct kelas)>1
  ) then
    raise exception 'Bentrok: ada guru yang dijadwalkan di lebih dari satu kelas pada hari dan JP yang sama';
  end if;

  if exists (
    select 1 from public.sikur_kelas k
    where not exists (select 1 from pg_temp.sikur_import_rows r where r.kelas=k.kelas)
  ) then
    raise exception 'Jadwal belum mencakup seluruh kelas aktif pada Data Master';
  end if;

  select count(distinct kelas) into v_classes from pg_temp.sikur_import_rows;

  select coalesce(max(versi),0)+1 into v_version
  from public.sikur_periode_semester
  where tahun_ajaran=p_tahun_ajaran and semester=p_semester;

  insert into public.sikur_periode_semester
    (tahun_ajaran,semester,versi,aktif,created_by)
  values
    (p_tahun_ajaran,p_semester,v_version,false,v_user)
  returning id into v_period_id;

  update public.sikur_periode_semester set aktif=false where aktif=true;
  update public.sikur_periode_semester set aktif=true where id=v_period_id;

  insert into public.sikur_jadwal(period_id,hari,jam_ke,kelas,kode_mapel,kode_guru)
  select v_period_id,hari,jam_ke,kelas,kode_mapel,kode_guru
  from pg_temp.sikur_import_rows
  order by case hari
    when 'Senin' then 1 when 'Selasa' then 2 when 'Rabu' then 3
    when 'Kamis' then 4 when 'Jumat' then 5 when 'Sabtu' then 6
    else 7 end, jam_ke, kelas;

  return jsonb_build_object(
    'periode_id',v_period_id,
    'tahun_ajaran',p_tahun_ajaran,
    'semester',p_semester,
    'versi',v_version,
    'jumlah_jadwal',v_count,
    'jumlah_kelas',v_classes
  );
end;
$function$;

create or replace function public.sikur_aktifkan_periode_semester(p_periode_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_user uuid := auth.uid();
  v_period public.sikur_periode_semester%rowtype;
  v_count integer;
begin
  if v_user is null or public.sikur_my_role() not in ('admin','waka') then
    raise exception 'Hanya Admin/Waka Kurikulum yang dapat mengaktifkan periode';
  end if;

  perform pg_advisory_xact_lock(hashtext('sikur_semester_switch'));
  select * into v_period from public.sikur_periode_semester where id=p_periode_id;
  if not found then raise exception 'Arsip periode tidak ditemukan'; end if;

  select count(*) into v_count from public.sikur_jadwal where periode_id=p_periode_id;
  if v_count=0 then raise exception 'Arsip periode tidak memiliki jadwal'; end if;

  update public.sikur_periode_semester set aktif=false where aktif=true;
  update public.sikur_periode_semester set aktif=true where id=p_periode_id;

  return jsonb_build_object(
    'periode_id',v_period.id,
    'tahun_ajaran',v_period.tahun_ajaran,
    'semester',v_period.semester,
    'versi',v_period.versi,
    'jumlah_jadwal',v_count
  );
end;
$function$;

revoke all on function public.sikur_import_semester_schedule(text,text,jsonb) from public, anon;
grant execute on function public.sikur_import_semester_schedule(text,text,jsonb) to authenticated;
revoke all on function public.sikur_aktifkan_periode_semester(uuid) from public, anon;
grant execute on function public.sikur_aktifkan_periode_semester(uuid) to authenticated;

create or replace view public.v_sikur_jadwal_lengkap
with (security_invoker=true)
as
select
  j.id,
  j.hari,
  j.jam_ke,
  k.mulai,
  k.selesai,
  j.kelas,
  j.kode_mapel,
  m.nama_mapel,
  j.kode_guru,
  g.nama_guru
from public.sikur_jadwal j
join public.sikur_periode_semester p on p.id=j.periode_id and p.aktif=true
join public.sikur_jam_kbm k using (hari,jam_ke)
join public.sikur_mapel m using (kode_mapel)
join public.sikur_guru g using (kode_guru);

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
  join public.sikur_periode_semester ps on ps.id=j.periode_id and ps.aktif=true
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
