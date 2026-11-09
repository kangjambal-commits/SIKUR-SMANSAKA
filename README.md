# SIKUR SMANSAKA

## Pemetaan versi

- **Aplikasi HTML utama:** `index.html`, identitas antarmuka SIKUR v2.5.
- **PantauKBM:** `pantau/index.html`, aplikasi pelaporan terpisah.
- **React prototype:** `src/App.tsx`, masih berupa prototipe v4.2 dan belum menjadi entry point aplikasi HTML utama.
- **package.json 4.2.0:** identitas paket untuk prototipe Vite/React; angka ini tidak membuktikan bahwa antarmuka React tersebut sedang dipakai pada domain produksi.

Jangan mengganti entry point atau menaikkan nomor versi produksi sebelum migrasi dari aplikasi HTML ke React direncanakan dan diuji.

## Infrastruktur

- GitHub: repositori sumber kode.
- Vercel: hosting aplikasi web.
- Supabase: autentikasi, basis data, dan RPC PantauKBM.

## Pemulihan kata sandi

Aplikasi utama mengirim email pemulihan dengan redirect ke origin aplikasi yang sedang dibuka. Supabase Auth harus mengizinkan URL produksi:

`https://sikursmanskav4web.vercel.app/**`

Setelah pengguna membuka tautan, aplikasi menangani event `PASSWORD_RECOVERY` dan menyimpan kata sandi baru melalui Supabase Auth.

## PantauKBM

Kode akses koordinator terdiri dari enam karakter alfanumerik. Skrip `SIKUR_10_KODE_ACAK_PANTAUKBM.sql` menghasilkan kode acak dan menampilkan hasilnya hanya pada hasil SQL Editor. Jangan menaruh kode akses aktif dalam repositori publik.

`SIKUR_11_ROTASI_KODE_KOORDINATOR.sql` adalah skrip rotasi manual untuk membatalkan sesi koordinator lama dan menghasilkan kode baru. Skrip rotasi dan pembaruan PIN menggunakan bcrypt work factor 12 untuk hash PIN yang dibuat setelah pembaruan.

## Jadwal Khusus Sekolah

Menu **Jadwal Khusus** digunakan Admin/Waka Kurikulum untuk mengatur perubahan waktu KBM pada tanggal kegiatan tertentu. Satu pengaturan berlaku seragam untuk seluruh kelas. JP dapat diubah waktu mulai/selesainya atau dinonaktifkan pada tanggal tersebut.

- Jadwal mingguan reguler tidak ditimpa dan otomatis digunakan kembali di luar tanggal khusus.
- Dashboard, Jadwal Saya Hari Ini, dampak ketidakhadiran, dan PantauKBM mengikuti waktu khusus pada tanggal yang berlaku.
- Pengaturan disimpan pada tabel `sikur_jadwal_khusus` di Supabase dan disinkronkan antarpengguna melalui Realtime.
- Semua pengguna yang sudah login dapat membaca jadwal khusus; hanya role `admin` dan `waka` yang dapat membuat, mengubah, atau menghapus data.
- Jalankan `SIKUR_13_JADWAL_KHUSUS.sql` setelah `SIKUR_12_HARDENING_PANTAUKBM.sql` pada proyek Supabase yang benar.

## Catatan keamanan dan penerapan

- Jalankan SQL hanya setelah memeriksa target proyek Supabase dan membuat backup.
- Setelah rotasi kode, simpan hasil kode di tempat aman dan bagikan secara privat per kelas.
- Kebijakan `sikur_state` membatasi akses ke role `admin` dan `waka`; tabel sesi serta pembatasan login PantauKBM tidak dapat dibaca langsung melalui API.
- `SIKUR_12_HARDENING_PANTAUKBM.sql` mengonsolidasikan penguatan RLS, hak akses RPC, validasi kode kelas, verifikasi token, keamanan view jadwal, dan indeks relasi. Jalankan setelah skrip `SIKUR_09`, `SIKUR_10`, dan `SIKUR_11`. Skrip ini tidak merotasi kode koordinator.
- Hash PIN yang sudah tersimpan tidak diubah oleh hardening ini. Hash dengan work factor 12 diterapkan saat PIN berikutnya diatur ulang atau dirotasi.
- Perubahan pada branch pemeliharaan harus diuji melalui deployment preview sebelum digabungkan ke `main`.


## Pesan untuk Kelas

Menu **Pesan Kelas** digunakan Admin/Waka untuk mengirim informasi kepada satu kelas, beberapa kelas, atau seluruh kelas. Pesan dapat diberi prioritas biasa/penting, tanggal mulai tampil, tanggal akhir opsional, dan status aktif/nonaktif. Ketua kelas melihat pesan yang sesuai dengan kelasnya setelah masuk ke PantauKBM. Pesan hanya tampil selama masa berlakunya; menu ini tidak mengirim pesan WhatsApp otomatis.

- Pengiriman dan perubahan pesan dibatasi oleh RLS untuk role `admin` dan `waka`.
- PantauKBM mengambil pesan melalui RPC tervalidasi menggunakan token sesi kelas; tabel pesan tidak dibuka untuk akses langsung anon.
- Jalankan `SIKUR_14_PESAN_KELAS.sql` setelah `SIKUR_13_JADWAL_KHUSUS.sql` pada proyek Supabase yang benar.


## Periode Semester dan Impor Jadwal

Menu **Data Master → Periode Semester & Impor Jadwal** digunakan Admin/Waka untuk memasang jadwal baru dari Excel atau CSV.

Format lembar kerja:
- `Hari`
- `JP`
- `Kelas`
- `Kode Mapel`
- `Kode Guru`

Satu baris mewakili satu kelas pada satu JP. Kode harus sesuai dengan Data Master SIKUR. Semua kelas Data Master wajib tercakup; kombinasi hari/JP harus tersedia pada pengaturan Jam KBM.

Sebelum jadwal diaktifkan, aplikasi memeriksa kelas, guru, mata pelajaran, JP, duplikasi slot kelas, dan bentrok guru. Server mengulang validasi dan hanya menerima perubahan dari role `admin` atau `waka`.

**Jadwal lama tidak dihapus.** Setiap impor membuat versi periode baru; jadwal sebelumnya tetap berada di arsip dan dapat diaktifkan kembali. ID jadwal lama tetap dipertahankan karena masih dirujuk oleh laporan PantauKBM dan penugasan guru pengganti.

Urutan migrasi:
1. `SIKUR_15_SEMESTER_DAN_IMPOR_JADWAL.sql`
2. `SIKUR_16_UNIQUE_JADWAL_PER_PERIODE.sql`
3. `SIKUR_17_UNIQUE_GURU_SLOT_PER_PERIODE.sql`

Pengaturan waktu JP, daftar Guru Piket, dan penetapan Wali Kelas merupakan data terpisah; tinjau kembali saat pergantian semester. Data laporan KBM lama tetap tersimpan.
