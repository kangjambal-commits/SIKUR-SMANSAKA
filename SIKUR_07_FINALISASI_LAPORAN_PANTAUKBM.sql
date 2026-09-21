-- ============================================================
-- SIKUR / PantauKBM - Finalisasi pengiriman laporan
-- TA 2026/2027
-- Jalankan SETELAH SIKUR_06_PANTAUKBM_JADWAL_WIB.sql
-- ============================================================

create extension if not exists pgcrypto with schema extensions;

create or replace function public.sikur_lapor_kbm(
    p_token text, p_jadwal_id bigint, p_status text,
    p_jam_masuk time default null, p_jam_keluar time default null,
    p_keterangan text default null
)
returns bigint
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
    v_ketua public.sikur_ketua_kelas%rowtype;
    v_jadwal public.sikur_jadwal%rowtype;
    v_id bigint;
    v_tanggal date := (timezone('Asia/Jakarta',now()))::date;
    v_hari text;
begin
    select k.* into v_ketua
    from public.sikur_ketua_kelas_sesi s
    join public.sikur_ketua_kelas k on k.id=s.ketua_id
    where s.berlaku_sampai > now()
      and encode(extensions.digest(p_token,'sha256'),'hex') = s.token_hash
      and k.aktif = true
    order by s.id desc
    limit 1;

    if not found then
      raise exception 'Sesi PantauKBM tidak valid atau sudah berakhir';
    end if;

    select * into v_jadwal
    from public.sikur_jadwal
    where id = p_jadwal_id;

    if not found then raise exception 'Jadwal tidak ditemukan'; end if;
    if v_jadwal.kelas <> v_ketua.kelas then
      raise exception 'Jadwal bukan milik kelas pelapor';
    end if;

    v_hari := case extract(isodow from v_tanggal)
      when 1 then 'Senin' when 2 then 'Selasa' when 3 then 'Rabu'
      when 4 then 'Kamis' when 5 then 'Jumat' when 6 then 'Sabtu'
      else 'Minggu' end;

    if v_jadwal.hari <> v_hari then
      raise exception 'Laporan hanya dapat dibuat untuk jadwal hari ini';
    end if;

    if p_status not in (
      'Hadir','Terlambat','Belum Hadir',
      'Meninggalkan Kelas Sebelum Selesai','Tidak Hadir',
      'Guru Pengganti','Tugas Mandiri'
    ) then
      raise exception 'Status laporan tidak valid';
    end if;

    insert into public.sikur_monitoring_kbm
      (tanggal,kelas,jadwal_id,jam_ke,kode_guru,status_laporan,
       jam_masuk,jam_keluar,keterangan,pelapor_nama,pelapor_peran,status_verifikasi)
    values
      (v_tanggal,v_jadwal.kelas,v_jadwal.id,v_jadwal.jam_ke,v_jadwal.kode_guru,p_status,
       p_jam_masuk,p_jam_keluar,left(nullif(trim(p_keterangan),''),500),
       v_ketua.nama_ketua,'Ketua Kelas','Perlu Verifikasi')
    on conflict (tanggal,kelas,jadwal_id)
    do update set
      status_laporan=excluded.status_laporan,
      jam_masuk=excluded.jam_masuk,
      jam_keluar=excluded.jam_keluar,
      keterangan=excluded.keterangan,
      pelapor_nama=excluded.pelapor_nama,
      status_verifikasi='Perlu Verifikasi',
      catatan_verifikasi=null,
      diverifikasi_oleh=null,
      diverifikasi_pada=null,
      updated_at=now()
    returning id into v_id;

    return v_id;
end;
$$;

grant execute on function public.sikur_lapor_kbm(text,bigint,text,time,time,text)
to anon, authenticated;
