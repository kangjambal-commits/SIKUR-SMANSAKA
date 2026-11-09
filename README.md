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

## Catatan keamanan dan penerapan

- Jalankan SQL hanya setelah memeriksa target proyek Supabase dan membuat backup.
- Setelah rotasi kode, simpan hasil kode di tempat aman dan bagikan secara privat per kelas.
- Kebijakan `sikur_state` membatasi akses ke role `admin` dan `waka`; tabel sesi serta pembatasan login PantauKBM tidak dapat dibaca langsung melalui API.
- `SIKUR_12_HARDENING_PANTAUKBM.sql` mengonsolidasikan penguatan RLS, hak akses RPC, validasi kode kelas, verifikasi token, keamanan view jadwal, dan indeks relasi. Jalankan setelah skrip `SIKUR_09`, `SIKUR_10`, dan `SIKUR_11`. Skrip ini tidak merotasi kode koordinator.
- Hash PIN yang sudah tersimpan tidak diubah oleh hardening ini. Hash dengan work factor 12 diterapkan saat PIN berikutnya diatur ulang atau dirotasi.
- Perubahan pada branch pemeliharaan harus diuji melalui deployment preview sebelum digabungkan ke `main`.
