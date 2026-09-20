-- SIKUR SMANSAKA - izin kelola Wali Kelas untuk Admin/Waka
-- Jalankan sekali setelah SIKUR_02_WALI_KELAS_TA_2026_2027.sql

drop policy if exists "wali_kelas_manage_admin_waka" on public.sikur_wali_kelas;

create policy "wali_kelas_manage_admin_waka"
on public.sikur_wali_kelas
for all
to authenticated
using (
  exists (
    select 1 from public.sikur_profiles p
    where p.id = auth.uid()
      and p.role in ('admin','waka')
  )
)
with check (
  exists (
    select 1 from public.sikur_profiles p
    where p.id = auth.uid()
      and p.role in ('admin','waka')
  )
);
