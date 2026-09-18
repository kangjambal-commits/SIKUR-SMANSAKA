# SIKUR SMANSAKA v4.2 Auto Sync

Versi ini menambahkan sinkronisasi otomatis dengan Supabase.

- Setelah Cloud terhubung, perubahan data lokal otomatis dikirim ke cloud (debounce ±1,5 detik).
- Saat sesi cloud aktif dan aplikasi dibuka, versi cloud terbaru otomatis dimuat.
- Jika offline, perubahan tetap tersimpan di perangkat; setelah koneksi kembali, perubahan berikutnya akan tersinkron.
- Tombol Tarik/Kirim manual tetap tersedia sebagai cadangan.
- Backup JSON tetap disarankan sebelum perubahan besar.

Untuk deployment Vercel: upload folder ini sebagai proyek Vite.
