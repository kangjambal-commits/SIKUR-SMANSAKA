-- SIKUR_17_UNIQUE_GURU_SLOT_PER_PERIODE.sql
-- Guru tidak boleh mengajar dua kelas dalam slot yang sama pada semester yang sama.
-- Jadwal dari semester berbeda tetap disimpan untuk kebutuhan arsip.

drop index if exists public.uq_sikur_guru_slot;

create unique index if not exists uq_sikur_guru_slot_periode
  on public.sikur_jadwal(periode_id,hari,jam_ke,kode_guru);
