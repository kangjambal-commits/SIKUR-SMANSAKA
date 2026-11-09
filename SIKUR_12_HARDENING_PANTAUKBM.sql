-- =========================================================
-- SIKUR-SMANSAKA: HARDENING SECURITY PANTAUKBM
-- Tanggal: 9 November 2026
-- Jalankan setelah SIKUR_09, SIKUR_10, dan SIKUR_11.
-- Aman dijalankan ulang. Tidak merotasi PIN atau menghapus data.
-- =========================================================

begin;

-- 1. Sikur state: only authenticated admin/waka via RLS.
revoke all privileges on table public.sikur_state from public, anon, authenticated;
drop policy if exists "SIKUR authenticated read" on public.sikur_state;
drop policy if exists "SIKUR authenticated insert" on public.sikur_state;
drop policy if exists "SIKUR authenticated update" on public.sikur_state;
drop policy if exists sikur_state_admin_waka_all on public.sikur_state;
grant select, insert, update, delete on table public.sikur_state to authenticated;
create policy sikur_state_admin_waka_all
on public.sikur_state for all to authenticated
using (public.sikur_my_role() in ('admin','waka'))
with check (public.sikur_my_role() in ('admin','waka'));

-- 2. Internal PantauKBM tables are accessible only by SECURITY DEFINER RPCs.
revoke all privileges on table public.sikur_ketua_kelas_sesi
  from public, anon, authenticated;
revoke all privileges on table public.sikur_login_koordinator_guard
  from public, anon, authenticated;

-- 3. Coordinator login: validate class, normalize input, throttle bad PINs.
create or replace function public.sikur_login_ketua_kelas(p_kelas text, p_pin text)
returns table(kelas text, nama_ketua text, token text)
language plpgsql
security definer
set search_path = public, extensions
as $function$
declare
  v_row public.sikur_ketua_kelas%rowtype;
  v_guard public.sikur_login_koordinator_guard%rowtype;
  v_token text;
  v_pin_valid boolean := false;
  v_kelas text := upper(trim(coalesce(p_kelas, '')));
  v_pin text := upper(trim(coalesce(p_pin, '')));
begin
  if not exists (select 1 from public.sikur_kelas c where c.kelas = v_kelas) then
    raise exception 'Kelas atau kode akses tidak valid';
  end if;

  select * into v_guard
  from public.sikur_login_koordinator_guard g
  where g.kelas = v_kelas
  for update;

  if found and v_guard.blokir_sampai is not null and v_guard.blokir_sampai > now() then
    raise exception 'Terlalu banyak percobaan. Coba lagi beberapa menit.';
  end if;

  if v_pin ~ '^[A-Z0-9]{6}$' then
    select * into v_row
    from public.sikur_ketua_kelas k
    where k.tahun_ajaran = '2026/2027'
      and k.kelas = v_kelas
      and k.aktif = true
      and k.pin_hash = extensions.crypt(v_pin, k.pin_hash);
    v_pin_valid := found;
  end if;

  if not v_pin_valid then
    insert into public.sikur_login_koordinator_guard(kelas,gagal,blokir_sampai,updated_at)
    values(v_kelas,1,null,now())
    on conflict on constraint sikur_login_koordinator_guard_pkey do update set
      gagal = case
        when public.sikur_login_koordinator_guard.blokir_sampai is not null
         and public.sikur_login_koordinator_guard.blokir_sampai <= now()
        then 1 else public.sikur_login_koordinator_guard.gagal + 1 end,
      blokir_sampai = case
        when (case
          when public.sikur_login_koordinator_guard.blokir_sampai is not null
           and public.sikur_login_koordinator_guard.blokir_sampai <= now()
          then 1 else public.sikur_login_koordinator_guard.gagal + 1 end) >= 5
        then now() + interval '10 minutes' else null end,
      updated_at = now();
    return;
  end if;

  insert into public.sikur_login_koordinator_guard(kelas,gagal,blokir_sampai,updated_at)
  values(v_kelas,0,null,now())
  on conflict on constraint sikur_login_koordinator_guard_pkey
  do update set gagal=0,blokir_sampai=null,updated_at=now();

  v_token := encode(extensions.gen_random_bytes(24),'hex');
  insert into public.sikur_ketua_kelas_sesi(token_hash,ketua_id,berlaku_sampai)
  values(extensions.crypt(v_token,extensions.gen_salt('bf')),v_row.id,now()+interval '12 hours');

  return query select v_row.kelas,('Koordinator '||v_row.kelas)::text,v_token;
end;
$function$;

-- 4. Schedule RPC must verify the bcrypt token used by the login function.
create or replace function public.sikur_jadwal_ketua_hari_ini(p_token text)
returns table(
  jadwal_id bigint, hari text, jam_ke integer, kelas text,
  kode_guru text, nama_guru text, kode_mapel text, nama_mapel text,
  mulai time without time zone, selesai time without time zone,
  status_laporan text, jam_masuk time without time zone,
  jam_keluar time without time zone, keterangan text
)
language plpgsql
security definer
set search_path = public, extensions
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
    when 1 then 'Senin' when 2 then 'Selasa' when 3 then 'Rabu'
    when 4 then 'Kamis' when 5 then 'Jumat' when 6 then 'Sabtu'
    else 'Minggu' end;

  return query
  select j.id::bigint,j.hari::text,j.jam_ke::integer,j.kelas::text,
    j.kode_guru::text,g.nama_guru::text,j.kode_mapel::text,m.nama_mapel::text,
    kb.mulai::time,kb.selesai::time,mon.status_laporan::text,
    mon.jam_masuk::time,mon.jam_keluar::time,mon.keterangan::text
  from public.sikur_jadwal j
  join public.sikur_guru g on g.kode_guru=j.kode_guru
  join public.sikur_mapel m on m.kode_mapel=j.kode_mapel
  left join public.sikur_jam_kbm kb on kb.hari=j.hari and kb.jam_ke=j.jam_ke
  left join public.sikur_monitoring_kbm mon
    on mon.tanggal=v_tanggal and mon.kelas=j.kelas and mon.jadwal_id=j.id
  where j.kelas=v_ketua.kelas and j.hari=v_hari
  order by j.jam_ke;
end;
$function$;

-- 5. PIN resets use bcrypt cost 12 and revoke old device sessions.
create or replace function public.sikur_set_ketua_kelas(p_kelas text,p_nama text,p_pin text)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $function$
declare
  v_kelas text := upper(trim(coalesce(p_kelas,'')));
  v_pin text := upper(trim(coalesce(p_pin,'')));
  v_ketua_id bigint;
begin
  if not exists (
    select 1 from public.sikur_profiles p
    where p.id=auth.uid() and p.role in ('admin','waka')
  ) then raise exception 'Akses ditolak'; end if;

  if not exists (select 1 from public.sikur_kelas c where c.kelas=v_kelas) then
    raise exception 'Kelas tidak ditemukan';
  end if;

  if v_pin !~ '^[A-Z0-9]{6}$' then
    raise exception 'Kode akses harus 6 karakter huruf/angka';
  end if;

  insert into public.sikur_ketua_kelas(tahun_ajaran,kelas,nama_ketua,pin_hash,aktif)
  values('2026/2027',v_kelas,'Koordinator '||v_kelas,
         extensions.crypt(v_pin,extensions.gen_salt('bf',12)),true)
  on conflict (tahun_ajaran,kelas) do update set
    nama_ketua='Koordinator '||excluded.kelas,
    pin_hash=excluded.pin_hash,aktif=true,updated_at=now()
  returning id into v_ketua_id;

  delete from public.sikur_ketua_kelas_sesi where ketua_id=v_ketua_id;
end;
$function$;

-- 6. Restrict API execution to the roles the application requires.
revoke all on function public.sikur_my_role() from public, anon;
grant execute on function public.sikur_my_role() to authenticated;
revoke all on function public.sikur_new_user_profile() from public, anon, authenticated;

revoke all on function public.sikur_set_ketua_kelas(text,text,text) from public, anon;
grant execute on function public.sikur_set_ketua_kelas(text,text,text) to authenticated;
revoke all on function public.sikur_verifikasi_monitoring_kbm(bigint,text,text) from public, anon;
grant execute on function public.sikur_verifikasi_monitoring_kbm(bigint,text,text) to authenticated;

revoke all on function public.sikur_login_ketua_kelas(text,text) from public;
grant execute on function public.sikur_login_ketua_kelas(text,text) to anon, authenticated;
revoke all on function public.sikur_jadwal_ketua_hari_ini(text) from public;
grant execute on function public.sikur_jadwal_ketua_hari_ini(text) to anon, authenticated;
revoke all on function public.sikur_lapor_kbm(text,bigint,text,time without time zone,time without time zone,text) from public;
grant execute on function public.sikur_lapor_kbm(text,bigint,text,time without time zone,time without time zone,text)
  to anon, authenticated;

-- 7. The test view now follows the caller's RLS rules and is not public.
alter view public.v_sikur_jadwal_lengkap set (security_invoker = true);
revoke all privileges on table public.v_sikur_jadwal_lengkap from public, anon;
grant select on table public.v_sikur_jadwal_lengkap to authenticated;

-- 8. Supporting indexes for foreign-key relationships.
create index if not exists idx_sikur_agenda_created_by on public.sikur_agenda(created_by);
create index if not exists idx_sikur_jadwal_kelas on public.sikur_jadwal(kelas);
create index if not exists idx_sikur_jadwal_kode_guru on public.sikur_jadwal(kode_guru);
create index if not exists idx_sikur_jadwal_kode_mapel on public.sikur_jadwal(kode_mapel);
create index if not exists idx_sikur_ketidakhadiran_kode_guru on public.sikur_ketidakhadiran(kode_guru);
create index if not exists idx_sikur_ketua_kelas_kelas on public.sikur_ketua_kelas(kelas);
create index if not exists idx_sikur_ketua_kelas_sesi_ketua_id on public.sikur_ketua_kelas_sesi(ketua_id);
create index if not exists idx_sikur_monitoring_kbm_diverifikasi_oleh on public.sikur_monitoring_kbm(diverifikasi_oleh);
create index if not exists idx_sikur_monitoring_kbm_jadwal_id on public.sikur_monitoring_kbm(jadwal_id);
create index if not exists idx_sikur_pengganti_jadwal_id on public.sikur_pengganti(jadwal_id);
create index if not exists idx_sikur_pengganti_kode_guru_pengganti on public.sikur_pengganti(kode_guru_pengganti);
create index if not exists idx_sikur_pengumuman_created_by on public.sikur_pengumuman(created_by);
create index if not exists idx_sikur_perubahan_ruang_created_by on public.sikur_perubahan_ruang(created_by);
create index if not exists idx_sikur_perubahan_ruang_kelas on public.sikur_perubahan_ruang(kelas);
create index if not exists idx_sikur_profiles_kode_guru on public.sikur_profiles(kode_guru);
create index if not exists idx_sikur_wali_kelas_kelas on public.sikur_wali_kelas(kelas);
create index if not exists idx_sikur_wali_kelas_kode_guru on public.sikur_wali_kelas(kode_guru);

-- 9. Optimize authenticated identity lookups in RLS policies.
drop policy if exists profile_self_read on public.sikur_profiles;
create policy profile_self_read on public.sikur_profiles
for select to authenticated
using (id=(select auth.uid()) or public.sikur_my_role() in ('admin','waka'));

drop policy if exists wali_kelas_manage_admin_waka on public.sikur_wali_kelas;
create policy wali_kelas_manage_admin_waka on public.sikur_wali_kelas
for all to authenticated
using (exists (
  select 1 from public.sikur_profiles p
  where p.id=(select auth.uid()) and p.role in ('admin','waka')
))
with check (exists (
  select 1 from public.sikur_profiles p
  where p.id=(select auth.uid()) and p.role in ('admin','waka')
));

drop policy if exists monitoring_kbm_manage_admin_waka on public.sikur_monitoring_kbm;
create policy monitoring_kbm_manage_admin_waka on public.sikur_monitoring_kbm
for all to authenticated
using (exists (
  select 1 from public.sikur_profiles p
  where p.id=(select auth.uid()) and p.role in ('admin','waka')
))
with check (exists (
  select 1 from public.sikur_profiles p
  where p.id=(select auth.uid()) and p.role in ('admin','waka')
));

drop policy if exists ketua_kelas_manage_admin_waka on public.sikur_ketua_kelas;
create policy ketua_kelas_manage_admin_waka on public.sikur_ketua_kelas
for all to authenticated
using (exists (
  select 1 from public.sikur_profiles p
  where p.id=(select auth.uid()) and p.role in ('admin','waka')
))
with check (exists (
  select 1 from public.sikur_profiles p
  where p.id=(select auth.uid()) and p.role in ('admin','waka')
));

commit;
