-- SIKUR 11 - Rotasi aman kode akses PantauKBM
-- Jalankan hanya ketika seluruh kode akses koordinator perlu dirotasi.
-- Skrip menghasilkan kode baru untuk 27 kelas, menyimpan hash saja,
-- menghapus sesi lama, lalu menampilkan kode satu kali pada hasil query.
-- Tindakan ini langsung membatalkan seluruh sesi koordinator yang sedang aktif.
-- Simpan hasil query di tempat aman dan bagikan hanya kepada koordinator terkait.

create extension if not exists pgcrypto with schema extensions;

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
    select kelas
    from public.sikur_ketua_kelas
    where tahun_ajaran='2026/2027'
      and kelas = any(array[
        'X-A','X-B','X-C','X-D','X-E','X-F','X-G','X-H','X-I',
        'XI-A','XI-B','XI-C','XI-D','XI-E','XI-F','XI-G','XI-H','XI-I',
        'XII-A','XII-B','XII-C','XII-D','XII-E','XII-F','XII-G','XII-H','XII-I'
      ])
    order by kelas
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

delete from public.sikur_ketua_kelas_sesi;
delete from public.sikur_login_koordinator_guard;

select kelas,kode_akses
from pg_temp.sikur_generated_codes
order by kelas;
