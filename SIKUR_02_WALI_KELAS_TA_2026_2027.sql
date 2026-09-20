-- SIKUR SMANSAKA - Wali Kelas TA 2026/2027
create table if not exists public.sikur_wali_kelas (
  tahun_ajaran text not null,
  kelas text not null references public.sikur_kelas(kelas) on update cascade on delete restrict,
  kode_guru text not null references public.sikur_guru(kode_guru) on update cascade on delete restrict,
  updated_at timestamptz not null default now(),
  primary key (tahun_ajaran, kelas)
);

alter table public.sikur_wali_kelas enable row level security;

drop policy if exists "wali_kelas_read_authenticated" on public.sikur_wali_kelas;
create policy "wali_kelas_read_authenticated" on public.sikur_wali_kelas
for select to authenticated using (true);

-- Penulisan wali kelas dibatasi melalui role aplikasi (waka/admin) dan kebijakan RLS proyek.
-- Data resmi TA 2026/2027:
insert into public.sikur_wali_kelas (tahun_ajaran,kelas,kode_guru) values
('2026/2027','X-A','HILAL'),('2026/2027','X-B','BULUD'),('2026/2027','X-C','TIMAR'),
('2026/2027','X-D','ANISA'),('2026/2027','X-E','FANI'),('2026/2027','X-F','SYIFA'),
('2026/2027','X-G','KHAMDAN'),('2026/2027','X-H','AAS'),('2026/2027','X-I','LELA'),
('2026/2027','XI-A','WARID'),('2026/2027','XI-B','INDRA'),('2026/2027','XI-C','WIWI'),
('2026/2027','XI-D','TITIN'),('2026/2027','XI-E','NIA'),('2026/2027','XI-F','ISNANI'),
('2026/2027','XI-G','RINA'),('2026/2027','XI-H','AFIF'),('2026/2027','XI-I','HARDI'),
('2026/2027','XII-A','SUS'),('2026/2027','XII-B','FIRMAN'),('2026/2027','XII-C','LILIN'),
('2026/2027','XII-D','MANSUR'),('2026/2027','XII-E','TANTO'),('2026/2027','XII-F','ETI'),
('2026/2027','XII-G','IRMA'),('2026/2027','XII-H','MUDI'),('2026/2027','XII-I','INAYAH')
on conflict (tahun_ajaran,kelas) do update set kode_guru=excluded.kode_guru, updated_at=now();
