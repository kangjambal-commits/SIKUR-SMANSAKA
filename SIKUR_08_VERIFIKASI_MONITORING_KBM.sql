-- ============================================================
-- SIKUR / Monitoring KBM - Verifikasi Waka/Admin
-- TA 2026/2027
-- Jalankan SETELAH SIKUR_07_FINALISASI_LAPORAN_PANTAUKBM.sql
-- ============================================================

-- Perluas status verifikasi agar sebab resmi dapat dibedakan dari
-- laporan faktual ketua kelas.
alter table public.sikur_monitoring_kbm
  drop constraint if exists sikur_monitoring_kbm_status_verifikasi_check;

alter table public.sikur_monitoring_kbm
  add constraint sikur_monitoring_kbm_status_verifikasi_check
  check (status_verifikasi in (
    'Perlu Verifikasi',
    'Normal',
    'Tugas Kedinasan',
    'Tugas Sekolah',
    'Rapat KS',
    'Izin',
    'Sakit',
    'Tanpa Keterangan',
    'Sudah Ditindaklanjuti'
  ));

create or replace function public.sikur_verifikasi_monitoring_kbm(
  p_id bigint,
  p_status_verifikasi text,
  p_catatan text default null
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
  ) then
    raise exception 'Akses ditolak';
  end if;

  if p_status_verifikasi not in (
    'Perlu Verifikasi','Normal','Tugas Kedinasan','Tugas Sekolah',
    'Rapat KS','Izin','Sakit','Tanpa Keterangan','Sudah Ditindaklanjuti'
  ) then
    raise exception 'Status verifikasi tidak valid';
  end if;

  update public.sikur_monitoring_kbm
  set status_verifikasi=p_status_verifikasi,
      catatan_verifikasi=left(nullif(trim(p_catatan),''),500),
      diverifikasi_oleh=case when p_status_verifikasi='Perlu Verifikasi' then null else auth.uid() end,
      diverifikasi_pada=case when p_status_verifikasi='Perlu Verifikasi' then null else now() end,
      updated_at=now()
  where id=p_id;

  if not found then raise exception 'Laporan monitoring tidak ditemukan'; end if;
end;
$$;

grant execute on function public.sikur_verifikasi_monitoring_kbm(bigint,text,text)
to authenticated;
