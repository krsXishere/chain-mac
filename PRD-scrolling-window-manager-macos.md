# PRD v3 — ChainMac (Scrolling Window Manager macOS)

| Field | Isi |
|---|---|
| Nama produk | **ChainMac** (final) |
| Bundle ID | `app.chainmac` |
| Versi dokumen | 3.0 — menggantikan v2 |
| Tanggal | 2026-11-22 |
| Target parity | **ChainYourMac 2.5.0** (bukan PaperWM.spoon) |
| Stack | **SwiftUI app + AppKit, satu proses, tanpa Rust** |
| Config | TOML di `~/Library/Application Support/ChainMac/config.toml`, live reload |
| Platform | macOS 13 Ventura+, Apple silicon (keputusan Intel di §13) |
| Model bisnis | One-time purchase, lifetime license |
| Status | Draft untuk validasi |

---

## 0. Perubahan dari v2 (keputusan pemilik produk)

v2 menetapkan `SwiftUI app + engine Rust (fork Paneru)`. Itu dibatalkan.

1. **Stack = Swift only.** Satu executable Swift (SwiftPM), AXBridge + tiler + spring animation ditulis sendiri. Tidak ada helper Rust, tidak ada IPC socket, tidak ada fork Paneru, tidak ada kewajiban notice MIT pihak ketiga.
2. **Nama produk = ChainMac**, bundle ID `app.chainmac`. Semua rujukan `ScrollWM` dan `scrollwm://` diganti.
3. **Config tetap TOML** di Application Support, live reload. Alasan: setting berbasis file memudahkan diagnosa lewat support email, dan menulis/membaca satu file jauh lebih kecil daripada membangun database preference. GUI tetap satu-satunya antarmuka yang didokumentasikan.
4. Yang **tidak** berubah dari v2: target parity 26 fitur, seluruh spesifikasi UI/UX (§5), shortcut default, perilaku engine (§6), NFR, roadmap, acceptance checklist.

**Harga yang dibayar:** semua edge case macOS (Spaces, multi-display, sleep/wake, native tabs, dialog detection, swipe) harus dibangun dan diuji sendiri. Milestone bergeser dari "audit fork" menjadi "bangun dan buktikan per fitur". Lihat §11 untuk gate nyata, bukan asumsi.

---

## 1. Arti "Seperti ChainYourMac"

Parity didefinisikan dalam empat lapis:

| Lapis | Parity berarti | Tidak termasuk |
|---|---|---|
| **Fitur** | 26 fitur ChainYourMac 2.5.0 berjalan dengan perilaku setara | Fitur internal yang tidak terlihat |
| **UX** | Menu bar, struktur Settings, onboarding, Mac Setup, minimap, shortcut, default value | Copywriting, ikon, logo, nama, warna brand |
| **Arsitektur** | Tidak diparik. ChainMac adalah satu proses Swift; ChainYourMac memakai helper Rust | Source code ChainYourMac (closed) |
| **Distribusi** | DMG, Developer ID, notarization, Sparkle, lisensi sekali bayar | Server lisensi & akun mereka |

Lapis arsitektur dilepas secara sadar. Yang diuji adalah perilaku, bukan susunan proses.

Nama, logo, copy, dan aset visual ChainYourMac tidak disalin. Tidak ada kode pihak ketiga yang difork, sehingga tidak ada notice lisensi tambahan di luar dependensi SwiftPM yang dipakai (`swift-argument-parser` bila perlu, Sparkle untuk update).

---

## 2. Ringkasan Produk

ChainMac menempatkan setiap window sebagai kolom pada strip horizontal tanpa ujung, satu strip per display dan per macOS Space. Window baru masuk di samping window fokus; window lain tidak pernah mengecil. Navigasi lewat keyboard, swipe trackpad, scroll mouse, atau minimap. Layout, width, stack, tab, dan pin bertahan setelah restart dan sleep.

**Positioning:** "PaperWM/niri sebagai aplikasi native Mac: semua setting di GUI, animasi mengikuti refresh rate, tanpa SIP, tanpa proses latar terpisah."

### Goals

| ID | Goal | Ukuran |
|---|---|---|
| G1 | Parity fungsional 2.5.0 | 26/26 fitur lulus acceptance test (§11) |
| G2 | Terasa instan | Input-to-frame < 1 frame; animasi 60/120Hz |
| G3 | Setup tanpa file config | 100% setting punya kontrol GUI, apply instan |
| G4 | Layout tidak pernah hilang | Restore setelah restart, sleep, wake, unplug display |
| G5 | Ringan & privat | ≤ 45 MB satu proses, ≤ 2% CPU rata-rata, tanpa telemetry |

### Non-Goals

- Bukan grid tiler (bukan yabai/AeroSpace/Amethyst).
- Bukan snapper manual (bukan Rectangle/Magnet).
- Tidak ada Mac App Store (sandbox tidak kompatibel dengan AX + event tap).
- Tidak menyalin brand, copy, ikon, atau aset ChainYourMac.
- Tidak ada cloud sync / akun di v1.
- Tidak ada workspace virtual tambahan; memakai macOS Spaces apa adanya.
- Tidak ada helper/proses terpisah (lihat §0).

---

## 3. Target Pengguna

| Persona | Kebutuhan |
|---|---|
| **Niri/PaperWM refugee** | Model strip sama, keybinding ⌃⌥, tanpa config wajib |
| **Developer multi-monitor** | Stacks, tabs, pin, per-app rules, restore |
| **Buyer non-teknis** | Onboarding 5 langkah, GUI penuh, tidak perlu scripting |

---

## 4. Parity Scope — 26 Fitur ChainYourMac 2.5.0

Status: **D** = sudah ada di kode saat ini (terverifikasi lewat test atau hardware), **A** = perlu adaptasi dari yang ada, **B** = build baru belum ada kode.

| # | Fitur | Status | Kerja |
|---|---|---|---|
| 1 | Endless strip, satu per display per Space | A | Tiling dasar jalan; tambah keying per `(displayUUID, spaceID)` |
| 2 | Spring animation vsync-locked + shortcut instan | B | `CVDisplayLink`/`CADisplayLink` + spring, ukur latency |
| 3 | Stacks (accordion dalam kolom) | D | `ColumnLayout.swift` sudah stacked/accordion 28pt; verifikasi resize/reorder |
| 4 | Tabbed columns + tab bar | A | Mode `tabbed` sudah ada di model; tab bar UI belum |
| 5 | Width preset (25/33/50/66/75), wider/narrower, full, center | A | `ColumnState.widthRatio` ada; preset cycling + center modes belum |
| 6 | Gaps + Dock-aware sizing | A | `Gaps` ada dan diuji; Dock-aware sizing belum |
| 7 | Center-focused modes (Never/Overflow/Always) | B | Mode + perilaku scroll |
| 8 | Focus border + dim inactive | B | Border overlay window, dim level 5–60% |
| 9 | Strip indicator/minimap (frosted, ikon, klik, drag reorder) | B | `NSPanel` overlay + hit testing |
| 10 | Trackpad swipe 3/4 jari 1:1 + snap/free | B | Multitouch callback |
| 11 | Drag window ke kolom lain untuk reorder | B | Deteksi drag via AX position notification |
| 12 | Multi-monitor, send next display, disable per display | B | `CGDisplayBounds` per display + setting |
| 13 | Session restore (urutan, width, stack, tab, pin) | B | Tulis/baca state JSON; matching app+title+urutan |
| 14 | Launch at login + auto-start | B | `SMAppService` |
| 15 | Per-app rules (float / fixed slot) via app picker | B | Matcher + GUI |
| 16 | Automation: URL scheme, Raycast, CLI | B | `CFBundleURLTypes` + handler; CLI target terpisah |
| 17 | Sparkle update, log, self-healing restart | B | Sparkle 2 + rotasi log; watchdog tidak relevan (satu proses) |
| 18 | Native fullscreen dipasrahkan ke macOS | A | Deteksi fullscreen → exclude |
| 19 | No focus stealing | A | Terverifikasi di M0 hardware; tambah test regresi |
| 20 | Focus follows mouse / mouse follows focus | B | Dua toggle, default off |
| 21 | Guided start + Mac Setup | B | Wizard + checker + one-click fix |
| 22 | Pin column kiri/kanan + indikator | B | Model pinned column + batas gerak |
| 23 | Native tabs as one column | B | Deteksi `AXTabs` dan jadikan satu kolom |
| 24 | Dialogs & previews float otomatis | A | Filter `AXStandardWindow` ada; perluas untuk sheet/panel/Quick Look |
| 25 | Keep Original Height (opsional) | B | Mode tinggi + alignment top |
| 26 | Sleep/wake/lock/display wake recovery | B | Observasi `NSWorkspace` + `CGDisplayRegisterReconfigurationCallback` |

Kode yang sudah ada dan teruji saat ini: strip layout + gap math (`StripLayout.swift`, 7 test), kolom stacked/tabbed (`ColumnLayout.swift`), enumerasi window AX (`AXBridge.swift`), penempatan window (`Tiler.swift`, 5 test). Total 19 test lulus. Itu setara fitur 1 (sebagian), 3, dan penggerak fitur lain, bukan parity.

Tambahan yang ikut diparik karena terlihat di UI/dokumentasi ChainYourMac:

- Minimap interaktif: tahan tombol shortcut → tetap tampil; klik tile → jump; drag tile → reorder.
- Pin indicator: garis biru tipis di samping kolom pinned + ikon pin di tile minimap.
- Tab bar: ikon + judul, tab depan ter-highlight; opsi `tab_bar_titles` di file config.
- Default rule: Picture in Picture float.
- Recorder shortcut paham layout non-US (AZERTY/QWERTZ/Dvorak).
- Warning saat shortcut bentrok dengan macOS atau aksi lain.
- Reset to Defaults dengan file backup; reset shortcut terpisah.
- Settings apply instan, tanpa tombol Save dan tanpa restart.
- Config TOML di `~/Library/Application Support/ChainMac/config.toml`, live reload, "Reload from Disk".

---

## 5. UI/UX Specification

### 5.1 Information Architecture

```
Menu bar item
├── Status: Running / Stopped
├── Start / Stop / Restart
├── Actions ▸ (semua aksi, tanpa shortcut)
├── Settings… (⌘,)
├── Mac Setup…
├── Accessibility Settings
├── Launch at Login (toggle)
├── Check for Updates… / Restart to Install Update
└── Quit

Main window (sidebar)
├── Configuration
│   ├── General
│   ├── Displays
│   ├── Layout
│   ├── Preset Window Widths
│   ├── Appearance
│   ├── Gestures & Mouse
│   ├── Behavior
│   ├── Window Rules
│   └── Shortcuts
├── Mac Setup
├── Help
│   ├── Integrations (install CLI, export Raycast)
│   └── Settings File Reference
└── About / License / Updates
```

Perilaku window:
- Bisa ditutup tanpa mematikan engine. App tetap jalan di menu bar.
- `Show in Dock` off → hanya menu bar; Dock icon muncul saat window terbuka.
- Fixed shortcut saat window app depan: ⌘, Settings; ⇧⌘S start/stop; ⇧⌘R restart.

### 5.2 First Run (guided start)

1. **Install & buka** — app dari `/Applications` (izin AX terikat lokasi dan signature).
2. **Accessibility** — penjelasan satu izin, tombol ke System Settings, deteksi otomatis setelah granted. Tidak ada izin kedua: satu proses berarti satu entry.
3. **License key** — paste, aktivasi, status Running.
4. **Lima gerakan** — fokus L/R, pindah window L/R, center, cycle width, float.
5. **Mac Setup** — jalankan checker; perbaiki yang bisa dengan satu klik.

Nada copy: langsung, jujur soal batasan, tanpa jargon. Contoh: "macOS hanya mengizinkan app menggerakkan window lewat Accessibility. Ini satu-satunya izin yang diminta."

### 5.3 Mac Setup (checker)

| Cek | Aksi |
|---|---|
| Accessibility untuk ChainMac | Tombol ke System Settings, status live |
| `Displays have separate Spaces` | Panduan; butuh logout jika diubah |
| Gesture macOS yang bentrok dengan swipe 3/4 jari | Tawarkan ganti jumlah jari atau matikan gesture macOS |
| Stage Manager | Peringatkan agar off |
| macOS built-in window management | Peringatkan agar off |
| Window manager/snapper lain berjalan (Rectangle, Magnet, OneMenu, yabai, AeroSpace) | Daftar + saran quit |
| Susunan display horizontal | Saran susun vertikal untuk mengurangi bleed |

### 5.4 Settings — Kontrol & Default

**General**

| Kontrol | Default |
|---|---|
| Launch at Login | Off |
| Start Window Manager Automatically | On |
| Show This Window When App Opens | On |
| Show in Dock | On |
| Automatically Check for Updates | On |
| Check for Updates… | tombol |

**Displays**

| Kontrol | Default |
|---|---|
| Manage windows on `<display>` | On per display |
| Forget display yang tercatat tapi tidak terhubung | tombol |

**Layout**

| Kontrol | Range | Default |
|---|---|---|
| Gap Between Windows | 0–32 pt | 8 |
| Gap at Screen Edges | 0–32 pt | 8 |
| Keep Clear of the Dock | toggle | On |
| Keep Original Height | toggle | Off |
| Center Focused Column | Never / On Overflow / Always | Never |

**Preset Window Widths**

- Default: 25, 33, 50, 66, 75%.
- Klik untuk edit, `+` untuk tambah; integer 10–100; minimal satu; selalu terurut.

**Appearance**

| Kontrol | Range | Default |
|---|---|---|
| Animation | Smooth / Fast / Instant | Smooth |
| Focus Border | toggle | Off |
| Border Color | color well | Amber |
| Border Width | 1–8 | 2 |
| Corner Radius | 0–24 | 10 |
| Dim Inactive Windows | toggle | Off |
| Dim Strength | 5–60% | 25% |
| Strip Minimap | toggle | On |
| Interactive Minimap | toggle | On |
| Pin Indicator | toggle | On |

**Gestures & Mouse**

| Kontrol | Pilihan | Default |
|---|---|---|
| Swipe to Scroll the Strip | 4 Fingers / 3 Fingers / Off | 4 Fingers |
| Natural Swipe Direction | toggle | On |
| Swipe Settles | Snap / Free | Snap |
| Drag to Reorder | toggle | On |
| Scroll to Move Through the Strip | ⌃⌥ / ⌥⌘ / ⌃⌘ / Off | ⌃⌥ |

**Behavior**

| Kontrol | Default |
|---|---|
| Restore Layout After Restart | On |
| Native Tabs as One Column | On |
| Float Dialogs and Previews | On |
| Focus Follows Mouse | Off |
| Mouse Follows Focus | Off |

**Window Rules**

- Rule fields: app (picker dari app berjalan), optional title contains, name; action Float atau Always open at column (Automatic / posisi tetap); advanced: bundle ID, title regex, custom gaps.
- Rule dievaluasi ulang saat title berubah.
- Default rule: Picture in Picture → Float.

**Shortcuts**

- Semua aksi bisa direbind; satu aksi boleh banyak binding; `+` tambah, `×` hapus, Esc batal.
- Warning jika kombinasi dipakai macOS atau aksi lain.
- Reset to Defaults (shortcut saja) tanpa menyentuh setting lain.

### 5.5 Default Shortcuts (harus identik)

Semua default memakai ⌃⌥. Plain ⌥ tidak dipakai karena dipakai macOS untuk edit teks.

| Aksi | Default |
|---|---|
| Focus Left / Right | ⌃⌥← ⌃⌥→ · ⌃⌥H ⌃⌥L |
| Focus Up / Down | ⌃⌥↑ ⌃⌥↓ · ⌃⌥K ⌃⌥J |
| Focus First / Last | ⌃⌥⌘← / ⌃⌥⌘→ |
| 1 | Jump to 1–9 | ⌃⌥1…⌃⌥9 |
| 1b | Wrap: ← pada kolom pertama menuju kolom terakhir, → sebaliknya | ⌃⌥← / ⌃⌥→ |
| Show Strip (minimap) | ⌃⌥S |
| Move Window Left / Right | ⌃⌥⇧← → · ⌃⌥⇧H L |
| Move Window Up / Down | ⌃⌥⇧↑ ↓ · ⌃⌥⇧K J |
| Move to First / Last | ⌃⌥⌘⇧← / → |
| Move to 1–8 / Last | ⌃⌥⇧1…8 / ⌃⌥⇧9 |
| Resize Window (next preset) | ⌃⌥R |
| Full Width (toggle) | ⌃⌥F |
| Center Window | ⌃⌥C |
| Wider / Narrower | ⌃⌥= / ⌃⌥- |
| Taller / Shorter | ⌃⌥⇧= / ⌃⌥⇧- |
| Equal Heights | ⌃⌥0 |
| Stack Left / Stack Right | ⌃⌥] / ⌃⌥[ |
| Unstack / Unstack Left | ⌃⌥⇧] / ⌃⌥⇧[ |
| Tabs (stacked ↔ tabbed) | ⌃⌥⇧T |
| Pin Left / Pin Right | ⌃⌥P / ⌃⌥⇧P |
| Float / Unfloat | ⌃⌥T |
| Next Display | ⌃⌥N |
| Quit Window Manager | ⌃⌥Q |

### 5.6 Interaction Specs

**Minimap**
- Muncul saat navigasi; frosted material; satu tile per kolom berisi ikon app.
- Kolom fokus di-outline; kolom di luar viewport diredupkan.
- Kolom stacked/tabbed menampilkan semua ikon.
- Tahan tombol shortcut terakhir → tetap tampil.
- Klik tile → fokus window; drag tile → reorder kolom.
- `⌃⌥S` menampilkan kapan pun walau auto-minimap off.
- Interactive off → tidak menangkap klik/drag.

**Navigasi melingkar.** Strip adalah lingkaran, bukan garis. `⌃⌥←` pada kolom pertama menuju kolom terakhir, `⌃⌥→` pada kolom terakhir menuju kolom pertama. Tidak ada tombol yang "tidak melakukan apa-apa" di ujung strip. Pinned column dilewati; kolom scrolling tetap berurutan di antara keduanya.

**Pinned column**
- Full height di edge kiri/kanan; strip lain scroll di sisinya.
- Window lain tidak bisa melewati kolom pinned.
- Lebar pinned dibatasi agar selalu ada ruang strip; cycle width melewati preset yang tidak muat.
- Garis biru + ikon pin di minimap; bisa dimatikan.

**Tabbed column**
- Satu window mengisi kolom, tab bar di atas dengan ikon + judul.
- Klik tab atau ⌃⌥↑/↓ untuk pindah.
- Tinggi window berkurang untuk tab bar; minimap menampilkan semua ikon.
- Opsi `tab_bar_titles = false` di file config untuk tab bar tipis.

**Swipe**
- 1:1 mengikuti jari; lepas → Snap ke kolom terdekat (kiri/center/kanan) atau Free.
- Arah natural default on; jumlah jari 4 default.
- Swipe vertikal tetap milik Mission Control/App Exposé.

**Center modes**
- Never: scroll sejauh perlu agar kolom fokus terlihat.
- On Overflow: center hanya jika kolom tidak muat di samping kolom sebelumnya.
- Always: kolom fokus selalu di tengah.
- `⌃⌥C` center sekali tanpa mengubah mode.

**Full Width vs macOS fullscreen**
- `⌃⌥F` melebarkan kolom selebar layar, tetap di strip; tekan lagi kembali ke preset terkecil.
- Green button macOS fullscreen tidak disentuh.

**App dengan batas ukuran**
- Pelajari minimum width tiap window saat pertama kali; layout memakai lebar yang benar-benar bisa diterima.
- Window fixed-size (Calculator, System Settings) float otomatis.
- Window hampir selebar layar tetap di strip; window tunggal non-modal tetap di strip.

**Dialogs**
- Dialog, alert, modal, window menempel, Quick Look, image preview, floating panel → float.
- Open/Save sheet tidak diatur; jika lebih lebar dari window, strip bergeser secukupnya lalu kembali.

**Drag to reorder**
- Drag title bar ke kolom lain → swap posisi; drag di minimap → reorder.
- Tidak bisa melewati pinned column.

**Keep Original Height**
- Window mempertahankan tinggi saat dibuka, aligned top; Taller/Shorter mengubah tinggi window itu sendiri.

**Sleep & wake**
- Setelah sleep, lock, atau display wake: susun ulang otomatis tanpa restart.
- Tiap display mendapat window-nya kembali; display yang wake belakangan tetap dipulihkan.
- Unplug display → window pindah utuh ke display tersisa.

### 5.7 Visual Language

- **Native macOS**: system font (SF Pro), SF Symbols, standard control sizing, vibrancy/material untuk minimap, tanpa custom chrome di Settings.
- **Window chrome**: tab bar tipis dengan icon 16pt + judul; focus border opsional amber default, width 2, radius 10.
- **Warna**: netral sistem; satu aksen amber (focus) dan biru (pin). Tidak memakai palet brand ChainYourMac.
- **Motion**: spring critically damped; Smooth/Fast/Instant; hanya berjalan saat window bergerak; tidak ada animasi idle.
- **Ikon menu bar**: template monochrome; state Running vs Stopped dibedakan.
- **Voice**: kalimat pendek, aktif, jujur soal limit macOS. Tidak memakai copy ChainYourMac.

### 5.8 Accessibility

- Semua kontrol Settings punya label VoiceOver dan bisa dioperasikan keyboard.
- Shortcut bisa diubah/dimatikan; tidak ada aksi yang hanya bisa mouse.
- Kontras focus border dan tab bar memenuhi WCAG AA pada light/dark mode.
- Onboarding bisa dilewati dan dibuka lagi dari Help.

---

## 6. Perilaku Engine (Behavioral Rules)

Semua berjalan di satu proses; "engine" berarti lapisan tiler di dalam app.

1. **Window lifecycle**: enumerate saat start; subscribe create/destroy/move/resize/focus/title/role via AX observer; window baru disisipkan di kanan window fokus; window hilang → kolom dikompaksi.
2. **Filter**: hanya `AXStandardWindow`, visible, punya titlebar, bukan fullscreen; dialog/sheet/panel dikecualikan.
3. **No focus stealing**: window background yang muncul tidak mengambil fokus dan tidak menggeser strip.
4. **Space & display**: strip terpisah per `(displayUUID, spaceID)`; pindah Space tidak mencampur layout; window di semua-desktop ikut strip Space aktif.
5. **Rules**: float atau posisi kolom tetap; evaluasi ulang saat title berubah; regex/bundle ID; custom gaps.
6. **Restore**: simpan state saat perubahan (debounced); saat start cocokkan window berdasarkan app + title + urutan; window yang tidak muncul diabaikan dan layout dikompaksi.
7. **Self-healing**: tiler yang tidak bereaksi (AX observer putus) di-rebuild otomatis; alasan ditulis ke log. Tidak ada proses untuk di-restart, jadi "watchdog" berarti memantau observer, bukan proses.
8. **Log**: rotasi lokal di `~/Library/Logs/ChainMac/`; title hanya dicatat jika detailed logging diaktifkan.

---

## 7. Arsitektur & Stack

### 7.1 Keputusan Stack

| Layer | Pilihan | Catatan |
|---|---|---|
| App UI | **SwiftUI + AppKit** | Menu bar `NSStatusItem`, Settings SwiftUI, overlay minimap AppKit |
| Engine | **Swift, di dalam app yang sama** | AX via `ApplicationServices`, animasi via display link, spring ditulis sendiri |
| Config | TOML di Application Support | Live reload; GUI menulis file yang sama |
| Animasi | Spring, vsync-locked | Target 120Hz ProMotion |
| Update | Sparkle 2 (EdDSA) | Satu-satunya dependensi pihak ketiga wajib |
| Login item | `SMAppService` | Default off |
| Lisensi | Paddle / Lemon Squeezy / Dodo | Key + machine hash; toleransi offline |
| Distribusi | Developer ID + notarization + DMG | Non-sandboxed, di luar MAS |
| Build | SwiftPM (`Package.swift`), tanpa Xcode project wajib | `scripts/bundle.sh` merakit `.app` |

**Ditolak: fork Paneru.** Alasan v2 (edge case macOS sudah selesai di Paneru) tetap benar secara teknis, tetapi ditolak oleh pemilik produk: tidak mau menambah toolchain Rust, tidak mau dua proses, tidak mau menanggung kewajiban upstream rebase. Konsekuensinya dicatat di §12, bukan disembunyikan.

**Alternatif yang juga ditolak:** wrapper di atas daemon Paneru (masih butuh Rust + IPC), engine dari nol di Rust (sama, tanpa Paneru).

### 7.2 Process Model

```
ChainMac.app (satu proses Swift, target ≤ 45 MB)
├── NSStatusItem + Settings window + Onboarding
├── Minimap overlay window (NSPanel, non-activating)
├── Focus border / dim overlay windows
├── Hotkey + multitouch + scroll handling
├── Tiler (AX observer, layout, spring animation)
├── State persistence (JSON) + config TOML
└── License + Sparkle + URL handler
```

Target resource: ≤ 45 MB dengan 30 window; CPU rata-rata ≤ 2% satu core; energy impact ≤ 2; idle wakeups ≤ 30/menit. Angka ini turun dari 70 MB di v2 karena helper 25 MB hilang.

### 7.3 Modul Internal (tanpa IPC)

Tidak ada socket, tidak ada `send-cmd`, tidak ada JSON over pipe. Aksi adalah method pada `TilerController` yang dipanggil langsung dari menu bar, hotkey, URL handler, dan minimap.

```swift
enum TilerAction {
    case focus(Direction), focusIndex(Int)
    case move(Direction), moveToIndex(Int)
    case nextPreset, fullWidth, center
    case wider, narrower, taller, shorter, equalHeights
    case stack(Side), unstack, toggleTabs
    case pin(Side), float, unfloat
    case nextDisplay
}
```

Dua permukaan eksternal tetap ada karena dibutuhkan fitur 16:

- **URL scheme** `chainmac://focus/east`, `chainmac://move/west` — handler `application(_:open:)`.
- **CLI** `chainmac focus east` — target SwiftPM terpisah, mengirim URL ke app lewat `NSWorkspace`. Tidak butuh socket.

### 7.4 Data Model

State runtime disimpan sebagai JSON:

```json
{
  "displays": [
    {
      "displayUUID": "37D8832A-…",
      "spaces": {
        "1": {
          "focused": 2,
          "columns": [
            {"apps": ["com.apple.finder"], "titles": ["Downloads"], "ratio": 0.5,
             "mode": "tiled", "pinned": null}
          ]
        }
      }
    }
  ]
}
```

Config TOML (ditulis GUI, dibaca app, live reload):

```toml
[options]
gap = 8
edge_gap = 8
keep_clear_of_dock = true
center_focused = "never"          # never | overflow | always
keep_original_height = false

[[preset_widths]]
value = 25
# ...

[appearance]
animation = "smooth"              # smooth | fast | instant
focus_border = false
focus_border_color = "#FFB000"
focus_border_width = 2
focus_corner_radius = 10
dim_inactive = false
dim_strength = 25
minimap = true
minimap_interactive = true
pin_indicator = true

[gestures]
swipe_fingers = 4
natural_direction = true
swipe_settles = "snap"            # snap | free
drag_to_reorder = true
scroll_modifier = "ctrl+alt"

[behavior]
restore_layout = true
native_tabs_one_column = true
float_dialogs = true
focus_follows_mouse = false
mouse_follows_focus = false

[[window_rules]]
name = "Picture in Picture"
action = "float"
bundle_id = "com.apple.PictureInPicture"
```

Parsing TOML memakai `TOMLDecoder` atau parser minimal milik sendiri; keputusan di §13.

### 7.5 Modul App (Swift)

Struktur nyata saat ini dan yang dituju:

```
Package.swift                       ChainMac (exe), ScrollCore (lib), ChainMacCLI
Sources/ScrollCore/
├── Model.swift                     ColumnMode, ColumnState, WorkspaceState, Gaps   [ada]
├── StripLayout.swift               anchor tiling + columnWidth                    [ada]
├── ColumnLayout.swift              tiled / stacked / tabbed                       [ada]
├── AXBridge.swift                  AXWindowHandle, enumerasi, Diagnostics         [ada]
├── Tiler.swift                     size-then-position, Outcome                    [ada]
├── DisplayLink.swift               CADisplayLink wrapper + spring step            [B]
├── Presets.swift                   cycle width, full width, center modes           [B]
├── Restore.swift                   JSON state, matching app+title                  [B]
├── Rules.swift                     matcher float / fixed slot                     [B]
Sources/ChainMac/
├── main.swift                      NSStatusItem, Diagnostics                      [ada]
├── StatusItemController.swift      menu, state Running/Stopped                    [B]
├── SettingsWindow.swift            SwiftUI sidebar + sections                     [B]
├── ShortcutRecorder.swift          Carbon, non-US layouts                         [B]
├── ConfigFileBridge.swift          TOML read/write + reload                       [B]
├── MinimapPanel.swift              NSPanel, non-activating                        [B]
├── FocusBorderOverlay.swift        border + dim                                  [B]
├── GestureHandler.swift            swipe, scroll modifier                         [B]
├── OnboardingFlow.swift            wizard 5 langkah                               [B]
├── MacSetupChecker.swift           checker + one-click                            [B]
├── URLRouter.swift                 chainmac://…                                   [B]
└── Support/                        License, Sparkle, PermissionManager            [B]
Sources/ChainMacCLI/                `chainmac <action>` → URL                      [B]
Tests/ScrollCoreTests/              XCTest untuk logika murni                      [ada]
packaging/Info.plist                bundle id app.chainmac                         [ada]
scripts/bundle.sh                   rakit .app + codesign ad-hoc                   [ada]
```

### 7.6 Build & Repo

- Repo tunggal SwiftPM. `swift build -c release` menghasilkan executable; `scripts/bundle.sh` merakit `build/ChainMac.app` dan menandatanganinya.
- Distribusi: Developer ID + hardened runtime + notarization. Untuk build lokal, ad-hoc sign cukup, tetapi setiap rebuild mencabut izin Accessibility (kode berubah → signature berubah). Mitigasi di §12.
- Universal binary (arm64 + x86_64) kecuali Intel diputuskan tidak didukung.
- Simpan dSYM untuk crash symbolication.

---

## 8. Non-Functional Requirements

| Kategori | Target |
|---|---|
| Latency | Input → frame < 16,7 ms (p95 @60Hz), < 8,3 ms @120Hz |
| Animation | Spring vsync-locked; tidak ada jitter saat swipe |
| Memory | ≤ 45 MB dengan 30 window |
| CPU | Rata-rata ≤ 2% satu core; idle < 0,5% |
| Energy | Energy Impact ≤ 2 (skala Activity Monitor) |
| Idle wakeups | ≤ 30/menit |
| Startup | App siap < 1 detik; tiling siap < 500 ms |
| Stabilitas | Crash-free sessions ≥ 99,5%; observer AX pulih < 1 detik |
| Kompatibilitas | macOS 13/14/15/26; ProMotion; notch; multi-display; Stage Manager off |
| Izin | Accessibility saja; tidak ada Screen Recording/Input Monitoring/Full Disk |
| Privasi | Tanpa telemetry; network hanya lisensi, cek lisensi harian, update |
| Aksesibilitas | VoiceOver untuk semua kontrol; navigasi keyboard penuh |
| Keamanan | Hardened runtime, notarized, update EdDSA; config tidak berisi title |

### Network yang diizinkan (persis)

| Kapan | Tujuan | Data |
|---|---|---|
| Aktivasi/deaktivasi | Server lisensi | License key, product ID, hash satu arah hardware ID |
| Saat launch, maksimal 1×/hari | Pemeriksaan lisensi | License key + product ID |
| Tiap beberapa jam (bisa dimatikan) | Update feed | Request feed + download update |

---

## 9. Distribusi, Harga, Lisensi

- Harga acuan parity: 1 Mac $19.99; 3 Mac $49.99; 5 Mac $79.99; 20 Mac $299.99; lifetime, update gratis.
- Checkout: Dodo Payments / Paddle / Lemon Squeezy (merchant of record).
- Lisensi: key via email, aktivasi in-app, deactivate untuk pindah Mac, toleransi offline.
- DMG + Sparkle; tanpa akun; tanpa refund (kebijakan sendiri, opsional).
- Requirements: macOS 13+, Apple silicon (keputusan Intel terbuka).
- Support: email developer; halaman setup & troubleshooting.

---

## 10. Roadmap & Gates

Milestone v2 ("fork & audit") tidak berlaku. Gate sekarang berbasis bukti di hardware.

| Milestone | Deliverable | Gate |
|---|---|---|
| **M0 — Tiling terbukti** (sebagian selesai) | Strip + gap math + AX tiling | 3 window Finder ter-tile tanpa overhang; `Tiled n/n` benar; 19 test lulus |
| **M1 — Strip lengkap** | Preset width, center modes, full width, stack/tab, focus border | Fitur 1,2,4,5,6,7,8 lulus acceptance |
| **M2 — Kontrol** | Shortcut recorder, menu bar, Settings IA, config bridge | Semua setting mengubah perilaku dan persist |
| **M3 — Multi-display & state** | Per-display strip, restore, sleep/wake, unplug | Fitur 12,13,26 lulus |
| **M4 — Overlay & input** | Minimap, pin, swipe, drag reorder, rules, tabs as one column | Fitur 9,10,11,15,22,23,24,25 lulus |
| **M5 — Onboarding & automation** | Guided start, Mac Setup, URL/Raycast/CLI | Fitur 16,20,21 lulus |
| **M6 — Ship** | Signing, notarization, Sparkle, lisensi, DMG, beta | Gatekeeper bersih; update antar versi jalan; crash-free ≥ 99,5% |

---

## 11. Acceptance / Parity Checklist

| # | Uji | Lulus jika |
|---|---|---|
| 1 | Buka 5 window | Tidak ada yang berubah ukuran; strip memanjang |
| 2 | Tahan → | Fokus pindah, strip bergerak, animasi mulus di 60/120Hz |
| 3 | Stack 3 window, resize height | Accordion benar; equal heights bekerja |
| 4 | ⌃⌥⇧T | Tab bar muncul; klik tab & ↑/↓ berpindah |
| 5 | ⌃⌥R 5× | 25→33→50→66→75→25; full & center benar |
| 6 | Gap 0 dan 32 | Layout menyesuaikan; tidak menabrak Dock |
| 7 | Center mode Always | Kolom fokus selalu di tengah |
| 8 | Focus border on | Border amber 2pt, radius 10; dim 25% |
| 9 | Minimap | Tampil saat navigasi; klik jump; drag reorder |
| 10 | Swipe 4 jari | Strip mengikuti jari 1:1; snap saat lepas |
| 11 | Drag title bar ke kolom lain | Urutan berubah |
| 12 | 2 display + ⌃⌥N | Window pindah display dan ter-tile; disable per display bekerja |
| 13 | Restart app | Urutan, width, stack, tab, pin pulih |
| 14 | Launch at login on | App start di menu bar setelah login |
| 15 | Rule float untuk 1 app | Window app itu selalu float; regex title bekerja |
| 16 | `open -g "chainmac://focus/east"` | Fokus pindah tanpa app ke depan |
| 17 | Update dari build lama | Sparkle menawarkan dan memasang update |
| 18 | Green button fullscreen | macOS fullscreen normal; app tidak ikut |
| 19 | Buka window dari app background | Fokus tidak berpindah |
| 20 | Focus follows mouse on | Fokus mengikuti kursor; off → tidak |
| 21 | First run | 5 langkah selesai; Mac Setup menemukan konflik |
| 22 | Pin kiri | Kolom full height; strip scroll di samping; tidak bisa dilewati |
| 23 | Finder dengan 3 tab | Satu kolom, bukan tiga |
| 24 | Buka dialog/Quick Look | Float, tidak masuk strip |
| 25 | Keep Original Height on | Tinggi awal dipertahankan, aligned top |
| 26 | Sleep lalu wake | Layout pulih tanpa restart |

---

## 12. Risiko & Mitigasi

| Risiko | Dampak | Mitigasi |
|---|---|---|
| Semua edge case macOS harus dibangun sendiri (v2 mengandalkan Paneru) | Roadmap jauh lebih panjang dari v2 | Gate per milestone (§10); tidak ada klaim parity sebelum acceptance lulus |
| AX call lambat | Animasi patah | Batch, cache, coalesce; ukur dengan Instruments; animasi tidak menunggu AX selesai |
| Private SkyLight berubah (macOS 26/27) | Space/display rusak | Isolasi di satu modul; feature flag; fallback ke CGWindowList |
| Ad-hoc sign + setiap rebuild mencabut izin Accessibility | Development loop lambat | Self-signed certificate stabil untuk dev; Developer ID untuk rilis |
| Swipe bentrok gesture macOS | User bingung | Mac Setup mendeteksi + one-click |
| Shortcut bentrok | Aksi tidak jalan | Warning di recorder + daftar konflik |
| Brand/legal | Klaim | Tidak memakai nama/logo/copy/aset; tidak ada kode pihak ketiga yang difork |
| Apple silicon-only | Pasar lebih kecil | Keputusan di open questions |
| Lisensi dijual tanpa refund | Keluhan | Kebijakan jelas; trial opsional |

---

## 13. Pertanyaan Terbuka

1. Bundle ID final: `app.chainmac` atau `com.<domain>.chainmac`?
2. Intel: dukung (universal) atau Apple silicon-only seperti ChainYourMac?
3. Harga & trial: $19.99 tanpa trial, atau $24.99 + trial 14 hari?
4. Parser TOML: `TOMLDecoder` (dependensi) atau parser minimal ~150 baris untuk subset yang dipakai?
5. Siapa yang memiliki brand/UX copy final (hindari kemiripan dengan ChainYourMac)?
6. Payment provider: Dodo vs Paddle vs Lemon Squeezy.
7. Domain dan halaman support.

---

## 14. Lampiran

### A. Batasan macOS yang diterima (sama seperti ChainYourMac)

1. Window tidak bisa dipindah sepenuhnya off-screen; tersisa sliver di tepi atau tab kecil di sudut.
2. Deteksi drag antar Space/display tidak reliable; sediakan aksi eksplisit.
3. Fullscreen native milik macOS.
4. Susunan display vertikal mengurangi bleed antar monitor.
5. Tidak ada API publik untuk memindah window antar Space; pakai SkyLight/private API.

### B. Jejak keputusan stack

| Versi | Keputusan | Alasan |
|---|---|---|
| v1 | Swift only (draf) | Dibatalkan di v2 |
| v2 | SwiftUI + Rust fork Paneru | Dibatalkan di v3 |
| **v3** | **Swift only, satu proses** | Pemilik produk menolak toolchain Rust dan proses kedua |

Alasan teknis v2 tetap berlaku sebagian: menulis sendiri berarti mengulang edge case macOS. Itu diterima sebagai biaya, dicatat di §12.

### C. Kebijakan aset & lisensi

- Tidak ada kode pihak ketiga yang difork; tidak ada notice lisensi engine yang wajib.
- Dependensi wajib: Sparkle (MIT-style, notice disertakan di About).
- Jangan memakai nama, logo, ikon, screenshot, atau copy ChainYourMac.
- Jangan reverse engineer binary ChainYourMac.

---

*Dokumen ini menargetkan parity perilaku ChainYourMac 2.5.0. Angka performa adalah target, bukan hasil pengukuran. Semua nama produk pihak ketiga milik pemiliknya masing-masing.*
