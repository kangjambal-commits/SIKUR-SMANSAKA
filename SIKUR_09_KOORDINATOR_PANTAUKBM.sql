-- ============================================================
-- SIKUR 09 - PantauKBM: Koordinator + kode akses alfanumerik
-- Jalankan sekali di Supabase SQL Editor.
-- ============================================================

create extension if not exists pgcrypto;

-- Nama personal tidak lagi diperlukan. Nilai lama tetap boleh ada.
alter table public.sikur_ketua_kelas
  alter column nama_ketua drop not null;

-- Login tetap memakai RPC lama agar aplikasi lama tidak terputus,
-- tetapi kode akses sekarang boleh 6 karakter huruf/angka.
create or replace function public.sikur_login_ketua_kelas(
    p_kelas text,
    p_pin text
)
returns table(kelas text, nama_ketua text, token text)
language plpgsql
security definer
set search_path = public
as $$
declare
    v_row public.sikur_ketua_kelas%rowtype;
    v_token text;
begin
    select * into v_row
    from public.sikur_ketua_kelas k
    where k.tahun_ajaran='2026/2027'
      and k.kelas=p_kelas
      and k.aktif=true
      and k.pin_hash=crypt(upper(trim(p_pin)),k.pin_hash);

    if not found then return; end if;

    v_token := encode(gen_random_bytes(24),'hex');

    insert into public.sikur_ketua_kelas_sesi(token_hash, ketua_id, berlaku_sampai)
    values (crypt(v_token,gen_salt('bf')),v_row.id,now()+interval '12 hours');

    return query select v_row.kelas,('Koordinator '||v_row.kelas)::text,v_token;
end;
$$;

-- Set/ganti kode akses per kelas. p_nama dipertahankan agar kompatibel
-- dengan SIKUR lama, tetapi diabaikan dan diganti identitas Koordinator.
create or replace function public.sikur_set_ketua_kelas(
    p_kelas text,
    p_nama text,
    p_pin text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    if not exists (
      select 1 from public.sikur_profiles p
      where p.id=auth.uid() and p.role in ('admin','waka')
    ) then raise exception 'Akses ditolak'; end if;

    if upper(trim(p_pin)) !~ '^[A-Z0-9]{6}$'
      then raise exception 'Kode akses harus 6 karakter huruf/angka'; end if;

    insert into public.sikur_ketua_kelas(tahun_ajaran,kelas,nama_ketua,pin_hash,aktif)
    values ('2026/2027',p_kelas,'Koordinator '||p_kelas,crypt(upper(trim(p_pin)),gen_salt('bf')),true)
    on conflict (tahun_ajaran,kelas)
    do update set
      nama_ketua='Koordinator '||excluded.kelas,
      pin_hash=excluded.pin_hash,
      aktif=true,
      updated_at=now();
end;
$$;

-- Pelaporan menggunakan identitas Koordinator, bukan nama siswa.
create or replace function public.sikur_lapor_kbm(
    p_token text,
    p_jadwal_id bigint,
    p_status text,
    p_jam_masuk time default null,
    p_jam_keluar time default null,
    p_keterangan text default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
    v_ketua public.sikur_ketua_kelas%rowtype;
    v_jadwal public.sikur_jadwal%rowtype;
    v_id bigint;
    v_hari text;
begin
    select k.* into v_ketua
    from public.sikur_ketua_kelas_sesi s
    join public.sikur_ketua_kelas k on k.id=s.ketua_id
    where s.berlaku_sampai>now()
      and crypt(p_token,s.token_hash)=s.token_hash
      and k.aktif=true
    order by s.id desc limit 1;

    if not found then raise exception 'Sesi PantauKBM tidak valid atau sudah berakhir'; end if;

    select * into v_jadwal from public.sikur_jadwal where id=p_jadwal_id;
    if not found then raise exception 'Jadwal tidak ditemukan'; end if;
    if v_jadwal.kelas<>v_ketua.kelas then raise exception 'Jadwal bukan milik kelas pelapor'; end if;

    v_hari := case extract(isodow from (now() at time zone 'Asia/Jakarta')::date)
      when 1 then 'Senin' when 2 then 'Selasa' when 3 then 'Rabu'
      when 4 then 'Kamis' when 5 then 'Jumat' when 6 then 'Sabtu' else 'Minggu' end;
    if v_jadwal.hari<>v_hari then raise exception 'Laporan hanya dapat dibuat untuk jadwal hari ini'; end if;

    if p_status not in ('Hadir','Terlambat','Belum Hadir','Meninggalkan Kelas Sebelum Selesai','Tidak Hadir','Guru Pengganti','Tugas Mandiri')
      then raise exception 'Status laporan tidak valid'; end if;

    insert into public.sikur_monitoring_kbm
      (tanggal,kelas,jadwal_id,jam_ke,kode_guru,status_laporan,jam_masuk,jam_keluar,keterangan,pelapor_nama,pelapor_peran,status_verifikasi)
    values
      ((now() at time zone 'Asia/Jakarta')::date,v_jadwal.kelas,v_jadwal.id,v_jadwal.jam_ke,v_jadwal.kode_guru,p_status,p_jam_masuk,p_jam_keluar,left(nullif(trim(p_keterangan),''),500),'Koordinator '||v_ketua.kelas,'Koordinator','Perlu Verifikasi')
    on conflict (tanggal,kelas,jadwal_id)
    do update set
      status_laporan=excluded.status_laporan,
      jam_masuk=excluded.jam_masuk,
      jam_keluar=excluded.jam_keluar,
      keterangan=excluded.keterangan,
      pelapor_nama=excluded.pelapor_nama,
      pelapor_peran=excluded.pelapor_peran,
      status_verifikasi='Perlu Verifikasi',
      catatan_verifikasi=null,
      diverifikasi_oleh=null,
      diverifikasi_pada=null,
      updated_at=now()
    returning id into v_id;

    return v_id;
end;
$$;

grant execute on function public.sikur_login_ketua_kelas(text,text) to anon, authenticated;
grant execute on function public.sikur_lapor_kbm(text,bigint,text,time,time,text) to anon, authenticated;
grant execute on function public.sikur_set_ketua_kelas(text,text,text) to authenticated;

-- ============================================================
-- Inisialisasi 27 kelas dan kode akses tetap
-- X-A s.d. X-I       = KODE01 s.d. KODE09
-- XI-A s.d. XI-I     = KODE10 s.d. KODE18
-- XII-A s.d. XII-I   = KODE19 s.d. KODE27
-- ============================================================

do $pantau$
declare
    v_kelas text;
    v_no integer := 0;
    v_tingkat text;
    v_huruf text;
    v_kode text;
begin
    foreach v_tingkat in array array['X','XI','XII'] loop
        foreach v_huruf in array array['A','B','C','D','E','F','G','H','I'] loop
            v_no := v_no + 1;
            v_kelas := v_tingkat || '-' || v_huruf;
            v_kode := 'KODE' || lpad(v_no::text,2,'0');

            insert into public.sikur_ketua_kelas
                (tahun_ajaran,kelas,nama_ketua,pin_hash,aktif)
            values
                ('2026/2027',v_kelas,'Koordinator '||v_kelas,
                 crypt(v_kode,gen_salt('bf')),true)
            on conflict (tahun_ajaran,kelas)
            do update set
                nama_ketua='Koordinator '||excluded.kelas,
                pin_hash=excluded.pin_hash,
                aktif=true,
                updated_at=now();
        end loop;
    end loop;
end;
$pantau$;
