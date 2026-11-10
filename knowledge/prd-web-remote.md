# PRD — Presentools Web Remote Control (Smartphone Presentation Controller)

- **Feature:** Web Remote Control (Smartphone / Wi-Fi Companion Remote)
- **Status:** Draft / Planned (Unit 7–11)
- **Author:** Antigravity / dev-meth v3.2
- **Target OS:** macOS 15.2+ (Native Swift / AppKit)
- **Dependencies:** 0 (Apple Network.framework, CoreGraphics, CoreImage, AppKit)

---

## 1. Executive Summary & Problem Statement

### Problem
Saat presentasi menggunakan Presentools, presenter saat ini harus menekan tombol keyboard (`⌥0`, `⌥1`, `⌥2`, `⌥3`, `⌥Esc`) atau menggerakkan kursor di Mac untuk mengganti efek penunjuk (Spotlight, Laser, Zoom Lens). Ini membatasi mobilitas presenter di panggung atau ruang rapat karena mereka harus berdiri dekat dengan laptop mereka atau membeli hardware remote terpisah (seperti Logitech Spotlight seharga Rp 2+ juta).

### Solution
Menghadirkan fitur **Web Remote Control** bawaan ke dalam Presentools:
1. Presentools menjalankan **embedded local HTTP server** di jaringan Wi-Fi yang sama (menggunakan native `Network.framework`).
2. Mac menyediakan jendela pop-up dengan **QR Code** yang di-generate secara native (`CIFilter`). Presenter cukup memindai QR Code menggunakan kamera smartphone (iOS / Android) tanpa install aplikasi apa pun di HP.
3. Web client di smartphone menyediakan interface kontrol ergonomis ala **Logitech Spotlight**:
   - **Slide Navigation**: Tombol besar **NEXT** & **PREVIOUS** (dan opsi **Blank Screen**) yang memicu tombol panah keyboard macOS ke Keynote, PowerPoint, Google Slides, Canva, atau PDF viewer.
   - **Effect Controller**: Tombol on/off untuk efek Presentools (**Spotlight**, **Laser Pointer**, **Zoom Lens**, dan **All Off** / Panic reset).
   - **Realtime Sync & Haptic Feedback**: Status efek di HP otomatis tersinkronisasi dengan status di Mac, disertai getaran haptik responsif saat tombol disentuh.

---

## 2. Goals & Non-Goals

### Goals
- **Zero Third-Party Dependency:** Dibangun 100% menggunakan framework native macOS (`Network`, `CoreGraphics`, `CoreImage`, `AppKit`).
- **Zero App Install on Phone:** Cukup buka browser bawaan smartphone (Safari / Chrome) via scan QR Code atau input URL IP lokal.
- **Ultra-low Latency:** Respon aksi dari sentuhan di HP hingga efek/slide berubah di Mac < 50ms di jaringan Wi-Fi lokal.
- **Universal Presentation Compatibility:** Slide clicker bekerja di aplikasi presentasi apa pun tanpa mengimpor slide atau mengubah alur kerja presenter.
- **Graceful Permission Degradation:** Jika izin *Accessibility* macOS belum aktif, sistem memberikan panduan jelas tanpa membuat app crash.

### Non-Goals (Out of Scope for v1)
- **Gyroscope Air-Mouse / 3D Pointer Tracking:** Menggerakkan kursor Mac secara continuous dengan sensor akselerometer HP (rentan drift, latency tinggi di browser, butuh WebSocket kompresi tinggi & sensor pairing rumit; dipertimbangkan untuk v2).
- **Cloud Relay / Internet Tunneling:** Tidak ada komunikasi lewat server cloud publik; murni koneksi lokal Wi-Fi LAN (aman, cepat, offline-friendly di gedung tanpa internet luar).
- **Deck Importer / Slide Viewer di HP:** Web remote tidak menampilkan slide deck / slide preview di HP (fokus murni sebagai physical remote replacement).

---

## 3. User Persona & Use Cases

### Persona
- **Presenter / Trainer / Lecturer**: Ingin leluasa bergerak di depan panggung atau audiens sambil mengendalikan slide presentasi dan efek spotlight/laser hanya berbekal smartphone di genggaman tangan.

### Use Cases
1. **Panggung Presentasi / Konferensi:**
   - Presenter menyalakan Presentools di Mac.
   - Klik menu "Web Remote…" di menu bar. Muncul QR Code dan alamat URL (misal: `http://192.168.1.55:8765`).
   - Presenter scan QR code pakai kamera iPhone/Android. Web remote terbuka seketika.
   - Presenter berjalan menjauhi laptop, menekan tombol **NEXT** di layar HP untuk ganti slide, dan menekan **Spotlight** untuk menyorot bagan penting di layar proyektor.
2. **Panic Clear / All Off:**
   - Presenter selesai menyorot bagian slide, menekan tombol **All Off** di HP. Layar kembali normal tanpa menyentuh keyboard Mac.
3. **Blackout / B-Key:**
   - Presenter ingin audiens fokus pada pemaparan lisan. Tekan tombol **Blank Screen** di HP untuk membuat proyektor hitam/pause.

---

## 4. Technical Architecture

```
┌────────────────────────────────────────────────────────────────────────┐
│                        macOS App (Presentools)                         │
│                                                                        │
│   ┌─────────────────────┐            ┌──────────────────────────────┐  │
│   │ RemoteControlWindow │            │       NetworkServer          │  │
│   │ - CIFilter (QRCode) │            │  - NWListener (Port 8765)    │  │
│   │ - IP Discovery      │            │  - Lightweight HTTP Router   │  │
│   │ - Link Display      │            │  - Static Asset Delivery     │  │
│   └──────────┬──────────┘            └──────────────┬───────────────┘  │
│              │                                      │                  │
│              ▼                                      ▼                  │
│   ┌─────────────────────┐            ┌──────────────────────────────┐  │
│   │   Menu Bar Item     │            │    SlideController (CGEvent) │  │
│   │   - Remote Control… │            │  - Next: Right Arrow (0x7C)  │  │
│   │   - Server Status   │            │  - Prev: Left Arrow (0x7B)   │  │
│   └─────────────────────┘            │  - Blank: 'B' Key (0x0B)     │  │
│                                      └──────────────┬───────────────┘  │
│                                                     │                  │
│                                                     ▼                  │
│                                      ┌──────────────────────────────┐  │
│                                      │   Presentools.set(effect)    │  │
│                                      │ - .none / .spotlight / .laser│  │
│                                      │ - .zoom                      │  │
│                                      └──────────────────────────────┘  │
└─────────────────────────────────────────────────────▲──────────────────┘
                                                      │ HTTP REST (LAN)
                                                      │ POST /api/slide
                                                      │ POST /api/effect
                                                      │ GET  /api/status
                                       ┌──────────────┴──────────────────┐
                                       │        Mobile Web Client        │
                                       │    (Safari / Chrome on Phone)   │
                                       │ - Clean Dark Logitech Style UI  │
                                       │ - Touch-optimized & Haptic Vibe │
                                       │ - Active State Indicator        │
                                       └─────────────────────────────────┘
```

### 4.1 Networking & HTTP Server
- Menggunakan `Network.framework` (`NWListener`, `NWConnection` dengan `NWParameters.tcp`).
- Port default: `8765` (fallback ke port dinamis jika bentrok).
- Deteksi IP Wi-Fi lokal: menggunakan `getifaddrs` POSIX C-bridge, mencari interface `en0` (atau `en1`) berstatus IPv4 `AF_INET`.

### 4.2 Keyboard Event Emulation (`SlideController`)
- Meniru tombol fisik keyboard menggunakan CoreGraphics event injection:
  - `CGEvent(keyboardEventSource: nil, virtualKey: 124, keyDown: true)?.post(tap: .cghidEventTap)` (Right Arrow / Next)
  - `CGEvent(keyboardEventSource: nil, virtualKey: 123, keyDown: true)?.post(tap: .cghidEventTap)` (Left Arrow / Prev)
  - `CGEvent(keyboardEventSource: nil, virtualKey: 11, keyDown: true)?.post(tap: .cghidEventTap)` ('B' key / Blank Screen)
- Accessibility Check: `AXIsProcessTrusted()` untuk mendeteksi apakah Presentools diizinkan mengirim key event. Jika belum, API mengembalikan response status `requiresAccessibilityPermission: true`.

### 4.3 QR Code Generation (`RemoteControlWindow`)
- Menggunakan `CIFilter(name: "CIQRCodeGenerator")` dari CoreImage.
- Transformasi bitmap tajam menggunakan `CGAffineTransform(scaleX: 10, y: 10)` dan filter `kCIInterpolationNone` sehingga QR Code tajam dan mudah dibaca oleh kamera smartphone.

---

## 5. API Contracts & Endpoints

| Method | Endpoint | Payload / Query | Response JSON | Keterangan |
|---|---|---|---|---|
| `GET` | `/` | - | `text/html` | Mengembalikan file HTML/CSS/JS client remote mandiri. |
| `GET` | `/api/status` | - | `{"effect": "spotlight", "accessibilityGranted": true}` | Polling status efek aktif & izin sistem. |
| `POST` | `/api/effect` | `{"effect": "spotlight"}` | `{"ok": true, "effect": "spotlight"}` | Mengubah efek aktif: `none`, `spotlight`, `laser`, `zoom`. |
| `POST` | `/api/slide` | `{"action": "next"}` | `{"ok": true, "action": "next"}` | Mengirim navigasi slide: `next`, `prev`, `blank`. |

---

## 6. UI/UX Interaction Design

### 6.1 Menu Bar macOS
- Menu bar Presentools ditambahkan sub-item:
  - **Web Remote…** (Membuka jendela QR Code & URL).
  - Tanda status server: Port aktif & IP lokal.

### 6.2 QR Code Pop-up Panel (macOS)
- Tampilan minimalis berlatar serasi macOS.
- Menampilkan:
  - Gambar QR Code (240x240 pt).
  - URL teks: `http://192.168.1.15:8765`.
  - Tombol **Copy Link** & **Open in Browser**.
  - Switch On/Off Server.
  - Catatan: *"Hubungkan smartphone Anda ke jaringan Wi-Fi yang sama, lalu scan QR Code di atas."*

### 6.3 Smartphone Web Remote Interface
- Desain bertema gelap elegan (*matte dark slate & neon accents*).
- **Layout Tiga Zona**:
  1. **Header**: Nama app + Status koneksi indicator (🟢 Connected / 🔴 Reconnecting).
  2. **Zona Utama (Slide Controls)**:
     - Tombol **NEXT** besar di bagian tengah-bawah yang mudah dijangkau jempol.
     - Tombol **PREV** di kiri.
     - Tombol **BLANK** di kanan.
  3. **Zona Bawah (Effect Selector)**:
     - 4 tombol tab / pill: **Off**, **Spotlight**, **Laser**, **Zoom**.
     - Tombol yang aktif diberi aksen warna cerah (Spotlight = amber glow, Laser = red glow, Zoom = cyan glow).
- **Micro-interactions**:
  - `navigator.vibrate(40)` untuk haptic tap yang renyah di setiap penekanan tombol.
  - `touch-action: manipulation` untuk menghilangkan jeda 300ms tap di iOS/Android Safari.

---

## 7. Implementation Plan (Units of Work)

Sesuai metodologi **dev-meth v3.2**, pengerjaan dipecah menjadi unit-unit terukur dan dapat diverifikasi:

- [ ] **Unit 7 — IP Discovery & Slide Key Simulator**
  - Buat helper deteksi IP lokal Wi-Fi (`getifaddrs`).
  - Buat `SlideController.swift` dengan simulasi `CGEvent` (Left, Right, 'B') dan pengecekan `AXIsProcessTrusted()`.
  - Verifikasi: CLI / unit call simulasi event.
- [ ] **Unit 8 — Embedded HTTP Network Server (`NetworkServer.swift`)**
  - Implementasi HTTP Server berbasis `Network.framework` (`NWListener`).
  - Parsing request sederhana (GET `/`, GET `/api/status`, POST `/api/effect`, POST `/api/slide`).
  - Verifikasi: `curl http://localhost:8765/api/status` & `curl -X POST -d '{"effect":"laser"}' http://localhost:8765/api/effect`.
- [ ] **Unit 9 — Web Remote Client UI (`WebRemoteUI.swift`)**
  - HTML/CSS/JS mandiri tertanam dalam binary (single-string asset tanpa butuh folder terpisah).
  - Tampilan mobile-first, dark sleek presentation remote, tombol Next/Prev, effect selector, haptic feedback.
  - Verifikasi: Buka di Safari / Chrome mobile simulator.
- [ ] **Unit 10 — QR Code Generator & Window Panel (`RemoteControlWindow.swift`)**
  - CoreImage `CIQRCodeGenerator` rendering ke `NSImage`.
  - Jendela pop-up NSWindow dengan QR code, link, dan tombol copy.
  - Tambah menu "Web Remote…" ke `main.swift`.
  - Verifikasi: Scan QR Code dari perangkat nyata.
- [ ] **Unit 11 — Self-test & Bundle Integration**
  - Integrasikan ke `SelfTest.swift` dan `bundle.sh`.
  - Build `.app`, verifikasi `swift build` 0 warning 0 error, build DMG.
