# macOS 27 Overlay — gotcha & API terverifikasi

**Source:** SDK 27.0 di mesin ini (Xcode 27.0, Swift 6.4) + `main.swift` Unit 1 · `[2026-09-30]` · fase: Phase 2

Empat API yang wajib benar di overlay window, dan tiga di antaranya adalah bug yang hanya muncul saat presentasi. Semuanya diverifikasi terhadap header/interface SDK 27 di mesin ini, bukan dari hafalan.

## Key Takeaways

- **`ignoresMouseEvents` — AppKit TIDAK punya parameter forward.** Header SDK 27 (`NSWindow.h:795`) cuma `@property BOOL ignoresMouseEvents;` — satu BOOL, tanpa opsi. Klaim lama bahwa butuh `{ forward: true }` itu **konsep Electron, salah untuk AppKit**. macOS otomatis meneruskan event ke window di bawah. Verified by header + run: `clickThrough: true`, mouse normal.
- **`canJoinAllSpaces` + `fullScreenAuxiliary`.** Fullscreen di macOS = Space baru. Overlay yang tidak ikut pindah ke Space itu tidak terlihat saat presentasi fullscreen. Dua flag ini wajib: `NSWindow.collectionBehavior.insert(.canJoinAllSpaces)` dan `.fullScreenAuxiliary`.
- **Satu overlay window per display, bukan satu global.** Kalau presenter pindah monitor, presenter di monitor kedua tidak punya overlay.
- **`setFrame(constrainFrameRect(screen.frame, to: screen), display: true)`** — konversi koordinat screen→window. Display sekunder **di atas atau di kiri** primary (origin Y negatif) salah tempat kalau `screen.frame` dipakai langsung. Terverifikasi di mesin ini: monitor kedua `3440,-218 1080x1920`.

## Timers: `Timer` subclass tidak bisa

`Timer.init(timeInterval:target:selector:...)` menolak `target: nil` / `selector: nil` saat di-subclass — compile error. Yang dipakai: `DispatchSource.makeTimerSource(queue: .main)` + `MainActor.assumeIsolated` di handler. Queue `.main` dijamin jalan di main thread, jadi `assumeIsolated` aman di sini.

## Swift 6 strict concurrency

`NSApplicationDelegate` harus `@MainActor`. Tanpa itu, akses property `overlays`/`poller` dari delegate callback = compile error. Dan stdout ke file itu **block-buffered** — run kelihatan diam padahal jalan; butuh `fflush(stdout)`.

## API yang sudah diverifikasi (bukan dari hafalan)

| API | Status | Cara verifikasi |
|---|---|---|
| `CGPreflightScreenCaptureAccess()` | **returns `Bool`** | compile + run di Unit 1 |
| `CGPreflightScreenCaptureAccessStatus` | **tidak ada di SDK 27** | compile error |
| `SCShareableContent.excludingDesktopWindows(_:onScreenWindowsOnly:)` | ada, async | compile + run |
| `GlassButtonStyle`, `GlassProminentButtonStyle` | ada di SwiftUI 27 | grep `arm64e-apple-macos.swiftinterface` |
| `NSGlassEffectView` | ada di AppKit | header `NSGlassEffectView.h` |
| `NSGlassEffectView.effectIsInteractive` | ada, `API_AVAILABLE(macos(27.0))` | header |
| modifier `glassProminent` | ada di SwiftUI 27 | grep swiftinterface |

## SCK display count trap

`SCShareableContent` melaporkan **0 display(s)** untuk binary SwiftPM yang belum dibundle jadi `.app`. Proses tanpa identitas bundle tidak dikenali ScreenCaptureKit di macOS 15+. Ini bukan bug — hilang setelah Info.plist ada. **Kalau masih 0 setelah Unit 6, itu masalah beneran** dan jangan diabaikan.

## Open Questions

- [ ] Apakah overlay benar-benar ikut ke Space saat presentasi **fullscreen**. Flag sudah diset, tapi belum diuji di app fullscreen nyata — harus test manual, tidak bisa dari CLI.

## Related

[[KNOWLEDGE]] · [[history]]
