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
  select * into v_guard from public.sikur_login_koordinator_guard g where g.kelas=p_kelas;
  if found and v_guard.blokir_sampai is not null and v_guard.blokir_sampai>now() then
    raise exception 'Terlalu banyak percobaan. Coba lagi beberapa menit.';
  end if;

  select * into v_row from public.sikur_ketua_kelas k
  where k.tahun_ajaran='2026/2027' and k.kelas=p_kelas and k.aktif=true
    and k.pin_hash=extensions.crypt(upper(trim(p_pin)),k.pin_hash);

  if not found then
    insert into public.sikur_login_koordinator_guard(kelas,gagal,blokir_sampai,updated_at)
    values(p_kelas,1,null,now())
    on conflict(kelas) do update set
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
  values(p_kelas,0,null,now())
  on conflict(kelas) do update set gagal=0,blokir_sampai=null,updated_at=now();

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

-- Ganti 27 kode akses dengan kode acak.
do $codes$
declare r record;
begin
  for r in
    select * from (values
      ('X-A','BYBJH7'),
      ('X-B','LUN7Z5'),
      ('X-C','L4N7CM'),
      ('X-D','GQRJ7R'),
      ('X-E','QGPZ7Y'),
      ('X-F','PF7TY3'),
      ('X-G','78R88X'),
      ('X-H','F82NLS'),
      ('X-I','8GEWRK'),
      ('XI-A','P5D88Q'),
      ('XI-B','8F6ZGL'),
      ('XI-C','JXQ7GK'),
      ('XI-D','ZFT6TR'),
      ('XI-E','FDPYV3'),
      ('XI-F','69MAFN'),
      ('XI-G','T7EB7Z'),
      ('XI-H','S2YUEB'),
      ('XI-I','FUL22X'),
      ('XII-A','J9JUF6'),
      ('XII-B','GV4J2D'),
      ('XII-C','LJGUMA'),
      ('XII-D','XHVHBN'),
      ('XII-E','9G5MTS'),
      ('XII-F','BRPNDE'),
      ('XII-G','6G5RUN'),
      ('XII-H','8XTHV4'),
      ('XII-I','AAPTMK')
    ) as x(kelas,kode)
  loop
    update public.sikur_ketua_kelas
    set nama_ketua='Koordinator '||r.kelas,
        pin_hash=extensions.crypt(r.kode,extensions.gen_salt('bf')),
        aktif=true,updated_at=now()
    where tahun_ajaran='2026/2027' and kelas=r.kelas;
  end loop;
end;
$codes$;

delete from public.sikur_ketua_kelas_sesi;
delete from public.sikur_login_koordinator_guard;

grant execute on function public.sikur_login_ketua_kelas(text,text) to anon,authenticated;
