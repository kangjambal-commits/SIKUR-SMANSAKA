-- SIKUR 10 - Kode acak PantauKBM + pembatasan percobaan login
-- Jalankan sekali setelah SIKUR_09.

create extension if not exists pgcrypto with schema extensions;

create table if not exists public.sikur_login_koordinator_guard (
  kelas text primary key,
  gagal integer not null default 0,
  blokir_sampai timestamptz,
  updated_at timestamptz not null default now()
);
alter table public.sikur_login_koordinator_guard enable row level security;

create or replace function public.sikur_login_ketua_kelas(p_kelas text,p_pin text)
returns table(kelas text,nama_ketua text,token text)
language plpgsql security definer
set search_path = public, extensions
as $func$
declare
  v_row public.sikur_ketua_kelas%rowtype;
  v_guard public.sikur_login_koordinator_guard%rowtype;
  v_token text;
begin
  select * into v_guard from public.sikur_login_koordinator_guard g where g.kelas = sikur_login_ketua_kelas.p_kelas;
  if found and v_guard.blokir_sampai is not null and v_guard.blokir_sampai>now() then
    raise exception 'Terlalu banyak percobaan. Coba lagi beberapa menit.';
  end if;

  select * into v_row from public.sikur_ketua_kelas k
  where k.tahun_ajaran='2026/2027' and k.kelas = sikur_login_ketua_kelas.p_kelas and k.aktif=true
    and k.pin_hash=extensions.crypt(upper(trim(p_pin)),k.pin_hash);

  if not found then
    insert into public.sikur_login_koordinator_guard(kelas,gagal,blokir_sampai,updated_at)
    values(sikur_login_ketua_kelas.p_kelas,1,null,now())
    on conflict on constraint sikur_login_koordinator_guard_pkey do update set
      gagal=case when public.sikur_login_koordinator_guard.blokir_sampai is not null
                     and public.sikur_login_koordinator_guard.blokir_sampai<=now()
                 then 1 else public.sikur_login_koordinator_guard.gagal+1 end,
      blokir_sampai=case when
          (case when public.sikur_login_koordinator_guard.blokir_sampai is not null
                     and public.sikur_login_koordinator_guard.blokir_sampai<=now()
                then 1 else public.sikur_login_koordinator_guard.gagal+1 end)>=5
        then now()+interval '10 minutes' else null end,
      updated_at=now();
    return;
  end if;

  insert into public.sikur_login_koordinator_guard(kelas,gagal,blokir_sampai,updated_at)
  values(sikur_login_ketua_kelas.p_kelas,0,null,now())
  on conflict on constraint sikur_login_koordinator_guard_pkey do update set gagal=0,blokir_sampai=null,updated_at=now();

  v_token:=encode(extensions.gen_random_bytes(24),'hex');
  insert into public.sikur_ketua_kelas_sesi(token_hash,ketua_id,berlaku_sampai)
  values(extensions.crypt(v_token,extensions.gen_salt('bf')),v_row.id,now()+interval '12 hours');

  return query select v_row.kelas,('Koordinator '||v_row.kelas)::text,v_token;
end;
$func$;

alter function public.sikur_lapor_kbm(text,bigint,text,time,time,text)
set search_path = public, extensions;
alter function public.sikur_set_ketua_kelas(text,text,text)
set search_path = public, extensions;

-- Rotasi 27 kode akses secara acak. Kode hanya ditampilkan pada hasil
-- SQL Editor saat skrip dijalankan; tidak disimpan sebagai teks di repositori.
create temporary table if not exists sikur_generated_codes (
  kelas text primary key,
  kode_akses text not null
) on commit preserve rows;
truncate table pg_temp.sikur_generated_codes;

do $codes$
declare
  r record;
  v_bytes bytea;
  v_code text;
  v_i integer;
  v_alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
begin
  for r in
    select k.kelas
    from public.sikur_ketua_kelas k
    where k.tahun_ajaran='2026/2027'
      and k.kelas = any(array[
        'X-A','X-B','X-C','X-D','X-E','X-F','X-G','X-H','X-I',
        'XI-A','XI-B','XI-C','XI-D','XI-E','XI-F','XI-G','XI-H','XI-I',
        'XII-A','XII-B','XII-C','XII-D','XII-E','XII-F','XII-G','XII-H','XII-I'
      ])
    order by k.kelas
  loop
    v_bytes := extensions.gen_random_bytes(6);
    v_code := '';
    for v_i in 0..5 loop
      v_code := v_code || substr(v_alphabet, (get_byte(v_bytes,v_i) % length(v_alphabet)) + 1, 1);
    end loop;

    update public.sikur_ketua_kelas
    set nama_ketua='Koordinator '||r.kelas,
        pin_hash=extensions.crypt(v_code,extensions.gen_salt('bf',12)),
        aktif=true,
        updated_at=now()
    where tahun_ajaran='2026/2027' and kelas=r.kelas;

    insert into pg_temp.sikur_generated_codes(kelas,kode_akses)
    values(r.kelas,v_code);
  end loop;
end;
$codes$;

-- Putuskan sesi lama dan reset penghitung percobaan login.
delete from public.sikur_ketua_kelas_sesi;
delete from public.sikur_login_koordinator_guard;

-- Simpan hasil query di tempat aman, lalu bagikan kode per kelas secara privat.
select kelas,kode_akses
from pg_temp.sikur_generated_codes
order by kelas;
