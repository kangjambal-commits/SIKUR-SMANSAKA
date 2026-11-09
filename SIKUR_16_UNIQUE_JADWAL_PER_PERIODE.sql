-- SIKUR_16_UNIQUE_JADWAL_PER_PERIODE.sql
-- Batas unik jadwal berlaku per periode, sehingga jadwal semester berbeda
-- dapat disimpan berdampingan tanpa menimpa ID jadwal yang direferensikan laporan.

alter table public.sikur_jadwal
  drop constraint if exists sikur_jadwal_hari_jam_ke_kelas_key;

create unique index if not exists uq_sikur_jadwal_periode_slot_kelas
  on public.sikur_jadwal(periode_id,hari,jam_ke,kelas);
