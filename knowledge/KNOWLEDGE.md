# Presentools — Project Knowledge

## Vision

Tool presentasi native macOS yang memberi 3 efek penunjuk — **spotlight**, **virtual zoom**, **laser pointer** — tanpa device remote, dan **tidak menyentuh aplikasi presentasi yang sedang dipakai**. Overlay melayang di atas layar apa pun (Keynote, PowerPoint, Google Slides, Zoom, apa saja).

Presenter tetap pakai app lamanya. Presentools cuma menimpa layar dengan efek visual yang mengikuti cursor.

Sasaran: 3 efek yang benar, ~500 baris logika, tray-only, tanpa window app yang mengganggu.

## Architecture

**Stack:** Swift 6.4 · macOS 27.0 (khusus 27, tanpa back-compat) · SwiftPM · nol dependency pihak ketiga

**Struktur:**

```
Package.swift                 SwiftPM manifest
Sources/presentools/
  main.swift                  entry point + permission check (akan diganti entry point app)
knowledge/                    output agent — start at knowledge/README.md
```

**Pola inti — 3 efek, 2 tier permission:**

| fitur | baca pixel layar? | permission |
|---|---|---|
| spotlight | tidak — cuma mask gelap + lubang terang | **tidak ada** |
| laser | tidak — cuma titik | **tidak ada** |
| virtual zoom | **ya** — butuh snapshot layar | **Screen Recording** |

Konsekuensi yang disengaja: kalau user deny Screen Recording, **2 dari 3 fitur tetap jalan sempurna**. Zoom jadi fitur degraded, bukan app mati.

**Pola visual yang tidak bisa dikompromi:** overlay wajib *fully transparent*. Kalau ada blur di overlay, spotlight tidak gelap dan zoom tidak tajam. Liquid Glass hanya boleh di panel kontrol + menu bar.

## Decisions

| Date | Decision | Reason | Rejected |
|------|----------|--------|----------|
| 2026-09-30 | Scope = 3 efek saja (spotlight/zoom/laser), tool bukan presenter app | Presenter app butuh import deck + renderer sendiri, effort 5x. Tool overlay jalan di app apa pun | Importer PDF/HTML deck; companion page web |
| 2026-09-30 | Swift / AppKit, bukan Electron | Electron = 150MB binary + 200MB RAM untuk 3 efek canvas. Overhead tanpa manfaat | Electron; Tauri (butuh Rust-side untested untuk `canJoinAllSpaces` + `ignoresMouseEvents`); Flutter (bisa cross-platform tapi ~15MB, v1 ini tidak perlu) |
| 2026-09-30 | Mac only v1 | Windows = rewrite (C#/WinUI), bukan port. Tapi logikanya cuma ~500 baris, jadi biaya riil kecil | — |
| 2026-09-30 | Deployment target **27.0** sahaja | Glass API native, tanpa branch/fallback | `15.0` + `if #available` (fallback ~15 baris tapi nyata, dan user pilih spesifik 27) |
| 2026-09-30 | Build = SwiftPM + script rakit `.app` | `xcodegen`/`tuist`/`swiftformat` tidak ada di mesin ini. Nol install baru | Hand-write `.xcodeproj`; `brew install xcodegen` |
| 2026-09-30 | Project di `<webroot>/lab/presentools` | Ada precedent non-PHP di `lab/` (`docker`, `f-license`). SwiftPM binary tidak butuh nginx | `~/code/presentools` |

## Progress

Semua unit selesai. `--selftest` PASS, zoom terbukti capture.

- [x] **Unit 1** — spike Screen Recording (`CGPreflightScreenCaptureAccess` + `SCShareableContent`)
- [x] **Unit 2** — overlay window per display + cursor poller 60Hz + menu bar item
- [x] **Unit 3** — spotlight: radial mask (`Effect.swift`)
- [x] **Unit 4** — laser: persistent dot (`Effect.swift`)
- [x] **Unit 5** — zoom lens: SCK capture 8Hz + magnify window (`ZoomLens.swift`)
- [x] **Unit 6** — `.app` terbundle 188KB, ad-hoc signed, tray-only, 4 global hotkey

**Bukti (run nyata, bukan baca kode):**

| cek | hasil |
|---|---|
| `swift build` (debug + release) | 0 warning, 0 error |
| `Presentools --selftest` | PASS (exit 0) — spotlight cursor=255 far=46, laser dot=255 rest=255, edge=45 |
| overlay live | `overlays: 2`, `clickThrough: true`, `level: 1000`, `polls: 121`/2s |
| SCK display | `sckDisplays: 2 [3440x1440 1080x1920]` — klaim "0 display" terbukti hilang setelah bundle |
| zoom capture | `captures=53` di t+7s (~7.6/s vs `captureHz=8`), `error=none` |
| hotkey | `4/4 registered` |
| binary | 188KB `.app`, RSS ~48MB |

Total 780 baris (7 file Swift + 41 baris `bundle.sh`), nol dependency pihak ketiga.

## Learnings

- [2026-09-30] `CGPreflightScreenCaptureAccess()` return **`Bool`**, bukan enum. `CGPreflightScreenCaptureAccessStatus` **tidak ada** di SDK 27. Authority untuk "apakah capture bisa jalan" = `SCShareableContent`, bukan API CG. (Compile error yang membongkar ini.)
- [2026-09-30] SwiftPM binary tanpa `.app` → `SCShareableContent` reported **0 display(s)**. Penyebab: proses tanpa identitas bundle tidak dikenali SCK di macOS 15+. Bukan bug — harus hilang setelah Unit 6. **Kalau masih 0 setelah dibundle, itu masalah beneran.**
- [2026-09-30] Liquid Glass di SDK 27: SwiftUI `GlassButtonStyle` + `GlassProminentButtonStyle`; AppKit `NSGlassEffectView` dengan `effectIsInteractive` (macOS 27.0). Ada modifier `glassProminent`. Verified via grep swiftinterface + header.
- [2026-09-30] **AppKit `ignoresMouseEvents` cuma `BOOL`, tidak ada parameter `forward`.** Klaim sebelumnya (`{ forward: true }`) itu API **Electron** — salah untuk AppKit. macOS otomatis teruskan event ke window bawah. Verified: `NSWindow.h:795` + run `clickThrough: true`.
- [2026-09-30] `Timer` subclass **tidak bisa** init dengan closure — `target: nil` / `selector: nil` ditolak compiler. Ganti `DispatchSource.makeTimerSource(queue: .main)` + `MainActor.assumeIsolated`.
- [2026-09-30] stdout **block-buffered** saat di-redirect ke file → run pertama kelihatan diam padahal jalan. `fflush(stdout)` setelah tiap print, atau run harus lewat terminal.
- [2026-09-30] `presentools` butuh `@MainActor` di class `NSApplicationDelegate` — tanpa itu akses `overlays`/`poller` dari delegate callback = compile error di Swift 6 strict concurrency.
- [2026-09-30] `setNeedsDisplay(_:)` menerima **NSRect**, bukan NSPoint.
- [2026-09-30] **`screencapture` + sample pixel GAGAL 2x sebagai verifikasi visual.** Cursor bergerak antar run (3305,54 → 1637,0) dan desktop gelap, jadi verdict INCONCLUSIVE. Ganti bitmap headless dengan bounds+cursor fixed di `SelfTest.swift`. Verifikasi visual butuh surface yang dikontrol, bukan desktop user.
- [2026-09-30] **Self-test menangkap bug NYATA di spotlight.** Radial gradient yang ramp linear dari radius ke corner layar cuma meredup 23% di corner, bukan 82% — spotlight bocor. Fix: ramp selesai di 2.2x radius lalu HOLD di dim penuh.
- [2026-09-30] Swift literal: string literal bersarang di dalam interpolasi (`"\(x.map { "\($0)" })"`) itu **illegal**. Hitset dulu ke variable.
- [2026-09-30] `CGRect.scaledBy` tidak ada; `Bool &=` tidak ada di Swift. Dua-duanya compile error, bukan runtime.
- [2026-09-30] `kVK_ANSI_*` **tidak contiguous** — 0 = 0x1D, tapi 1,2,3 = 0x12,0x13,0x14. Menebak pola `0x1C..0x1F` salah.
- [2026-09-30] **BUG NYATA di zoom, ketahuan saat verifikasi: yang lama bukan zoom, cuma miniature.** `SCScreenshotManager.captureImage(contentFilter:configuration:)` dengan `config.width=460` me-resize SELURUH display ke 460px, lalu `LensView.draw` cuma `ctx.draw(image, in: bounds)` tanpa crop. Semua hitungan koordinat SCK (`source` rect) cuma dipakai untuk border. Fix: `SCScreenshotManager.captureImage(in: rect)` — grab tepat satu rect, resolusi native. Koordinat SCK→AppKit yang di-flip pun sekarang benar-benar kepakai.
- [2026-09-30] **Ekspektasi "460px" gw salah, bukan kodenya.** `system_profiler` → `"UI Looks like: 3440 x 1440"` (bukan `@2x`) = dua display ini **non-retina**. Jadi 230pt → 231px itu backingScale 1.0 yang benar. Magnifikasi 2x di non-retina = point-doubling, **batas keras hardware**. Di display retina rect yang sama otomatis jadi 460px dan zoom langsung tajam — tanpa kode tambahan. Di proyektor zoom 2x memang lembut; itu inherent, bukan cacat.
- [2026-09-30] `SCScreenshotManager.captureImage(in:)` Swift-import-nya **non-optional + throws** (bukan `CGImage?`), jadi `try? ... as CGImage?` menghasilkan `CGImage??` dan `guard let` gagal. Probe over-engineered yang gw tulis (mean-luminance matching, 60 baris) dibuang — diganti satu konstanta + komentar jujur. Cara yang benar: baca signature dulu, jangan tulis probe sebelum tau bentuk API-nya.

## Files

| File | Purpose | Last Changed |
|------|---------|-------------|
| `Package.swift` | SwiftPM manifest, target macOS 27.0 | 2026-09-30 |
| `Sources/presentools/main.swift` | Entry point: NSApp tray-only, menu bar, effect dispatch, reporting | 2026-09-30 |
| `Sources/presentools/OverlayWindow.swift` | NSWindow + NSView per display, click-through, all-Spaces | 2026-09-30 |
| `Sources/presentools/CursorPoller.swift` | DispatchSourceTimer 60Hz, fan-out cursor ke semua overlay | 2026-09-30 |
| `Sources/presentools/Effect.swift` | Enum efek + render spotlight/laser, konstanta tampilan | 2026-09-30 |
| `Sources/presentools/ZoomLens.swift` | Jendela magnifier, `captureImage(in:)` 8Hz, koordinat SCK↔AppKit | 2026-09-30 |
| `Sources/presentools/HotKeyCenter.swift` | Carbon `RegisterEventHotKey` — AppKit tidak punya API global hotkey | 2026-09-30 |
| `Sources/presentools/SelfTest.swift` | Render headless ke bitmap, cek nilai piksel, exit code | 2026-09-30 |
| `bundle.sh` | Rakit `.app`: Info.plist (`LSUIElement`, usage description) + ad-hoc codesign | 2026-09-30 |
| `knowledge/README.md` | Index folder knowledge | 2026-09-30 |
| `knowledge/KNOWLEDGE.md` | Index ini | 2026-09-30 |
| `knowledge/history.md` | Timeline append-only | 2026-09-30 |
| `knowledge/macos-27-overlay.md` | Gotcha overlay + API terverifikasi | 2026-09-30 |
| `knowledge/research/logitech-spotlight.md` | Sumber device acuan | 2026-09-30 |

## Next

- **Test manual yang tidak bisa dari CLI (2 item):**
  1. Overlay di presentasi **fullscreen** (Keynote/PowerPoint Space baru). Flag `canJoinAllSpaces` + `fullScreenAuxiliary` sudah diset, belum diuji di app fullscreen nyata.
  2. `ZoomLens.rectOriginIsTopLeft` — `captureImage(in:)` cuma bilang "points on the screen space", nggak sebut originnya. Top-left = konvensi SCK lain, tapi **belum terverifikasi di slide nyata**. Kalau lens nunjuk bagian layar yang salah, flip 1 konstanta itu.
- Kalau lo pindah ke display retina, cek `lensImage:` di log — harus jadi `backingScale=2.0` dan zoom langsung tajam tanpa kode tambahan.
- Prioritas v2: freeze/blackout, anotasi, timer, presenter notes.

## Closed Questions

- [x] Native macOS Zoom (`⌥⇧8`) sebagai fallback? **Tidak** — user pilih lens saja, 2026-09-30
- [x] Discovery perlu banner notifikasi? **Tidak** — cukup ikon menu bar, 2026-09-30
- [x] `ignoresMouseEvents` perlu forward manual? **Tidak** — AppKit nggak punya parameter itu, otomatis
