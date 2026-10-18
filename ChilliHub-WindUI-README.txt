CHILLI HUB - WINDUI PORT

Jalankan: ChilliHub-WindUI-FULL.luau
Masuk ulang ke game terlebih dahulu, lalu paste seluruh isi file itu ke executor.
Jalankan hanya versi WindUI; jangan gabungkan dengan loader Diagnose/MeshFix/asli.

PERUBAHAN
- Bootstrap ChilliLibrary lama dilepas seluruhnya. Tidak ada constructor MeshPart/MeshId dekorasi lama.
- Kontrol lama dipetakan ke WindUI: toggle, dropdown, multi dropdown, slider, input, tombol, label/text.
- State bersama, ShowWhen, grup toggle eksklusif, dan sembilan lokasi canvas dihubungkan melalui adapter.
- Quick memakai tab pinned controls WindUI. Config memakai Save/Load terpisah di ChilliWindUI/Settings.json.
- Tata letak subkontrol diratakan di section WindUI. Layout quick bar dan panel settings lama tidak identik.
- WindUI, adapter, dan modul fitur digabung dalam file FULL; bootstrap tidak mengunduh ulang library atau script asli.
- Isi modul fitur setelah bootstrap dipertahankan; versi sumber dan WindUI dicatat di ChilliHub-WindUI-FULL-build.json.
- Perbaikan canvas: validasi class dipisah dari Instance.new agar pesan assert tidak terbaca sebagai parent.

VALIDASI
- Kompilasi sintaks Luau 0.743: loader, modul fitur, serta library WindUI lolos.
- Uji adapter dengan mock API yang memeriksa tipe parent Instance.new: state bersama, callback tertunda dropdown, silent update,
  slider numerik, ShowWhen, grup eksklusif, canvas/dock, dan Finalize lolos.
- Belum diuji langsung di Xeno. Ini bukan bukti semua fitur gameplay dapat berjalan di Xeno.
- Fungsi executor dan akses modul game tetap mengikuti implementasi aslinya.
- Error saat inisialisasi ditampilkan di panel; callback error ditulis ke console dan notifikasi WindUI.

SUMBER
https://github.com/Footagesus/WindUI
https://github.com/LSSOPS/OpenSource/blob/main/ChilliHub_Steal_An_Egg.lua
Lihat ChilliHub-WindUI-FULL-build.json untuk commit, hash, dan jumlah lokasi kontrol.
Lisensi WindUI: ChilliHub-WindUI-LICENSE.txt.
