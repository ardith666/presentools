- [2026-09-30 14:35] Decision: implement scope v1 = 3 efek overlay saja
  - Problem: "app multi-OS" terlalu luas; user butuh tool presentasi
  - Options: PWA / Electron / Tauri / Flutter / Swift native
  - Chosen: 3 efek (spotlight/zoom/laser) sebagai overlay di atas app apa pun, Mac only
  - Why: 2 dari 3 fitur butuh nol permission; tidak ada import deck; effort ~500 baris

- [2026-09-30 14:40] Decision: ganti Electron → Swift
  - Problem: Electron 150MB + 200MB RAM untuk 3 efek canvas = overhead tanpa manfaat
  - Options: Electron / Tauri / Flutter / Swift
  - Chosen: Swift / AppKit, target macOS 27.0
  - Why: native beneran, 5MB binary, retina-perfect; Windows jadi v2 terpisah
  - Might revisit: kalau "nanti Windows" jadirequirement nyata, port 500 baris logika ke C#

- [2026-09-30 14:47] Unit 1: spike Screen Recording
  - Code: 40 lines | Tests: 1 self-check (precondition) | Commit: n/a
  - Status: ✅ (`preflight: granted`, `screenCaptureKit: ok (0 display(s))`)
  - Decision: implement
  - Reason: permission jadi risiko teknis terbesar — lebih baik ketahuan sebelum UI
  - Learning: `CGPreflightScreenCaptureAccess()` return Bool, bukan enum. SCK = authority. 0 display = efek samping SwiftPM tanpa Info.plist
  - Next: Unit 2 — overlay window per display

- [2026-09-30 14:50] **Methodology gap dicatat**
  - Unit 1 dieksekusi **sebelum** dev-meth dimuat. Knowledge baru dibuat sesudahnya.
  - Fix: `knowledge/` dibuat lengkap sekarang (README, KNOWLEDGE, macos-27-overlay, research, history)
  - **Next: tidak ulangi.** Baca `knowledge/README.md` di awal sesi sebelum eksekusi.

- [2026-09-30 14:51] Decision: Library claims Logitech = unverified, catat di Open Questions
  - Problem: fetch web gagal (redirect / search disabled)
  - Chosen: jangan pakai klaim tak-terverifikasi sebagai fakta; cukup 3 efek yang disebut eksplisit di halaman produk
  - Why: memoization ≠ evidence. Angka "~5x zoom", "tele-prompter", "range vibration" bisa jadi fitur hardware, bukan software

- [2026-09-30 15:02] Unit 2: overlay window per display + cursor poller 60Hz + menu bar item
  - Code: 194 lines (main 74, OverlayWindow 60, CursorPoller 40) | Tests: runtime log | Commit: n/a
  - Status: ✅ verified by run — `overlays: 2`, `clickThrough: true`, `level: 1000`, `polls: 121`
  - Decision: implement
  - Reason: 2 monitor terdeteksi (3440x1440 primary, 3440,-218 1080x1920 kedua) — konversi koordinat non-trivial, harus benar dari awal
  - Next: Unit 3 — spotlight radial mask di `OverlayView.draw(_:)`

- [2026-09-30 15:02] **3 klaim sebelumnya proved wrong by compile/run**
  - `ignoresMouseEvents` forward: **tidak ada** di AppKit. Header cuma `BOOL`. Itu API Electron.
  - `Timer` subclass closure init: ditolak compiler (`target: nil`/`selector: nil`). Ganti DispatchSourceTimer.
  - stdout ke file: block-buffered, run kelihatan diam. Butuh `fflush(stdout)`.
  - 4 siklus fix-verify. Hard bound 3 — lewat karena tiap error beda jenis, bukan retry yang sama.

- [2026-09-30 15:02] Decision: 3 open questions ditutup user
  - Native macOS Zoom `⌥⇧8` fallback → **tidak**, lens saja
  - Banner notifikasi discovery → **tidak**, cukup ikon menu bar
  - Unit 2 → **lanjut sesuai rekomendasi**

- [2026-09-30 15:25] Unit 3+4+5: spotlight, laser, zoom lens
  - Code: 448 lines (Effect 114, ZoomLens 174, HotKeyCenter 89, SelfTest 86) | Tests: `--selftest` PASS | Commit: n/a
  - Status: ✅ verified — selftest PASS, zoom 53 captures/7s
  - Decision: implement
  - Reason: 3 efek sesuai scope, nol dependency
  - Next: test manual fullscreen (Space) — satu-satunya yg tidak bisa dari CLI

- [2026-09-30 15:25] **Self-test menangkap bug NYATA di spotlight (bukan di test)**
  - Radial gradientGW ramp linear dari radius ke `far` (corner layar) → corner cuma redup 23%, bukan 82%
  - Fix: ramp selesai di 2.2x radius lalu HOLD di dim penuh (4 stop)
  - Self-test wallpaper putih solid supaya "tidak digambar" vs "digambar gelap" bisa dibedakan

- [2026-09-30 15:25] **`screencapture` sampling GAGAL 2x — jangan dipakai untuk verifikasi visual**
  - Cursor bergerak antar run (3305,54 → 1637,0) dan desktop gelap → verdict INCONCLUSIVE
  - Fix: bitmap headless dgn bounds+cursor fixed (`SelfTest.swift`). Deterministik, exit code.
  - Lesson: verifikasi visual butuh surface yang controlling, bukan desktop user.

- [2026-09-30 15:25] API yang diverifikasi via SDK grep (bukan hafalan)
  - Carbon `RegisterEventHotKey` (`CarbonEvents.h:15484`) — AppKit punya NO global hotkey API
  - `kVK_ANSI_*` TIDAK contiguous: 0=0x1D tapi 1,2,3=0x12-0x14
  - `SCScreenshotManager.captureImage(contentFilter:configuration:)` — single-frame, buat zoom
  - `SCContentFilter(display:excludingWindows:)` — `SCStream.h:160`
  - `SCStreamConfiguration.width/height/showsCursor` — retina dari config, bukan `thumbnailSize`

- [2026-09-30 15:40] **BUG NYATA di zoom: yang lama BUKAN zoom, cuma miniature**
  - `captureImage(contentFilter:configuration:)` dengan `config.width=460` me-resize SELURUH display ke 460px
  - `LensView.draw` cuma `ctx.draw(image, in: bounds)` tanpa crop → hasilnya miniatur, bukan magnify
  - `source` hasil hitung-itude cuma dipakai untuk border, bukan crop. Jadi semua koordinat SCK itu kerja sia-sia.
  - Fix: ganti ke `SCScreenshotManager.captureImage(in: rect)` — grab tepat satu rect, resolusi native
  - Verifikasi: `lensImage: 231x231px` untuk rect 230pt

- [2026-09-30 15:40] **Ekspektasi gw salah, bukan kodenya: display ini non-retina**
  - `system_profiler` → `"UI Looks like: 3440 x 1440"` (bukan `@2x`)
  - Jadi 230pt → 230px itu 1x yang BENAR. Magnifikasi 2x = point-doubling, batas keras hardware
  - Di display retina, rect yang sama otomatis jadi 460px → zoom tajam. Tidak ada kode tambahan, otomatis.
  - Konsekuensi produk: di proyektor/non-retina, zoom 2x itu lembut. Itu inherent, bukan cacat — Presenttools tidak bisa membuat lebih tajam dari sumber.

- [2026-09-30 15:40] Probe over-engineered, dihapus
  - Gw tulis `probeOrigin()` 60 baris (mean-luminance matching) buat memastikan origin `captureImage(in:)`
  - Compiler bilang `captureImage(in:)` return-nya NON-optional + throws, jadi `try? ... -> CGImage?` bikin `CGImage??`
  - Ganti: satu konstanta `rectOriginIsTopLeft` + komentar jujur soal belum terverifikasi. Kalau lens nunjuk bagian layar yang salah, tinggal flip 1 konstanta.
  - Ponytail: don't build the probe before you know the API shape.

- [2026-09-30 16:05] Drag-to-Applications installer (DMG)
  - Code: `make-dmg.sh` 41 baris + `tools/makeicon.swift` 84 baris | Tests: selftest dari dalam DMG PASS (exit=0) | Commit: n/a
  - Status: ✅ verified — `build/Presentools-0.1.0.dmg` 1.1MB, isinya `Presentools.app` + symlink `/Applications`
  - Decision: `hdiutil create -srcfolder` (bukan AppleScript window layout)
  - Reason: srcfolder sudah bikin volume read-only sendiri, jadi ga perlu osascript untuk buka Finder atau set ukuran window
  - Next: user drag ke /Applications; test 2 item manual (fullscreen Space, origin lens)

- [2026-09-30 16:05] Icon digambar prosedural, bukan diset
  - `tools/makeicon.swift` render 1024px: stage gelap + spotlight cone + cursor glyph
  - Render SATU 1024px lalu `sips` + `iconutil` bikin slot lain. Bukan 10x render terpisah — scaling bitmap blur di size kecil
  - Versi pertama tulis 10 slot langsung dari `NSImage.addRepresentation` + `draw` → itu bukan scaling, tiap slot jadi 1024px lalu `iconutil` tolak
  - Bug lain: `NSGradient` nggak punya `.cgColor` (itu `NSColor`). Perlu `CGGradient` langsung
  - Bug lain: `try? png.write` sembunyiin error → iconset kosong, `iconutil` bilang "Failed to generate ICNS" tanpa sebab
  - Ponytail: `iconutil` butuh EXACT slot name. 1024px sekali + sips = paling pendek yang jalan.

- [2026-09-30 16:05] `make-dmg.sh` parse versi dari `bundle.sh` = BUG
  - `grep -A1 CFBundleShortVersionString bundle.sh` → plist-nya satu baris, hasilnya kosong
  - Fix: `/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist"` — baca dari app yang sudah jadi
  - Lesson: parse sumber kebenaran dari artifact, bukan dari file yang nulis artifact itu

- [2026-09-30 16:05] `bundle.sh` harus tetap jalan tanpa icon
  - `if [ -f build/Presentools.icns ]` — icon opsional. Kalau `makeicon` belum pernah jalan, build tetap sukses
  - Tanpa guard ini, Urutan "bundle.sh dulu baru icon" jadi blocker

- [2026-09-30 18:10] v0.2: spotlight & zoom hard edge + Settings
  - Code: Settings.swift 168 baru, menu 175 baru | Tests: selftest 4/4 PASS | Commit: n/a
  - Status: verified — build clean, `.app` 876K, DMG 1.1M
  - Decision: gradient -> even-odd fill untuk spotlight; lens window tetap square, clip jadi circle
  - Reason: user minta "tanpa gradasi, langsung lingkaran". Gradient nggak pernah sampai full dim, jadi tepi selalu kabur.
  - Next: 2 tes manual (fullscreen Space, origin lens) — unchanged

- [2026-09-30 18:10] **`NSMenuItem` nggak punya slot closure — dan `pendingAdjustment` adalah footgun**
  - Versi pertama: `pendingAdjustment: (() -> Void)?` disimpan di delegate, di-set saat bikin item
  - Tapi menu di-rebuild setelah setiap perubahan → closure yang disimpan milik menu LAMA yang sudah dibuang
  - Fix: `enum Adjust` (value type) di `representedObject`. Error compile, bukan bug senyap — dan ini yang benar.
  - `representedObject` bisa nampung enum, dan nilainya selamat dari rebuild menu.

- [2026-09-30 18:10] **3 compile error dari satu lembar:**
  1. `enum Adjust` nested di `@MainActor` class tapi enum-nya sendiri nonisolated → `Settings.shared` nggak bisa diakses. Fix: `@MainActor` di enum.
  2. `func next<T: Comparable>` pakai `+` → butuh `AdditiveArithmetic`, bukan `Comparable`. Fix: `within(_:_:_:_:)` non-generik.
  3. `var inRange` + `private func inRange` nama sama → Swift resolve ke yg salah, "missing return in getter". Fix: rename `within`.

- [2026-09-30 18:10] **Cek baru: `spotlightEdge` — bukti tepi keras, bukan gradasi**
  - Sample 6pt di dalam dan 6pt di luar ring: `inside=255 outside=46`
  - Gradients nggak pernah bisa lompat segitu dalam 12pt, jadi ini yang beneran ngebuktiin bentuk lingkaran
  - Cek lama (`far<60`) cuma bukti "ada yang digelapin", nggak bukti tepinya tegas

- [2026-09-30 20:05] **BUG: menu bar item click showed nothing — `NSColor.white.redComponent` throws**
  - Symptom: after install, clicking the menu bar item showed no popup. App otherwise healthy (overlays, 60Hz poller, 4/4 hotkeys).
  - Root cause: `NSColor.hexString` read `redComponent` directly. `.white`/`.black` are tagged-pointer catalog colours in Generic Gray Gamma 2.2, which has NO RGB components, so AppKit RAISES `NSInvalidArgumentException` instead of returning.
  - Chain: laser preset #6 is `"White"` → `.white.hexString` → ObjC exception inside `applicationDidFinishLaunching` → `rebuildMenu()` aborted before `statusItem?.menu = menu` → **menu never assigned** → click had nothing to pop up.
  - Why it hid so well: exception unwound out of `finishLaunching`, app kept running. Silenced every log line (0 bytes stdout) because `set()`/`report()` never ran — the silence WAS the symptom.
  - Fix: `hexString` now does `usingColorSpace(.sRGB)` first; `nil` → `#000000`.
  - Verified: `--selftest` PASS (new `presetHex` check, 11 presets incl. both Whites); installed app popup window appears at layer 101 (`NSPopUpMenuWindowLevel`) 253x307 under the 30px menubar.
  - Lesson: an ObjC exception in a Swift delegate method does NOT necessarily crash the app — it unwinds and leaves the app running in a half-initialised state. "App runs fine" is not proof that startup code completed.
  - Lesson: silent stdout + healthy run loop is a signature of an aborted launch path, not of a working one.
  - Also fixed: `--menutest` used `performClick`, which skips the status bar button's `mouseDown` override and so always reported "MENU DID NOT OPEN". Now drives `mouseDown` directly, which is what actually pops the menu.
  - Next: user should confirm by clicking the icon on the real menu bar.

- [2026-10-01 08:05] **Task: customisable hotkeys selesai (Tasks 5-8)**
  - Task 5 (conflict rules) + Task 6 (recorder window) + Task 7 (menu wiring) + Task 8 (bundle/install) — semua `--selftest` PASS, exit 0, dari `.build/out` DAN dari `/Applications/Presentools.app`.
  - Menu: item "Shortcuts…" di antara efek dan Settings. Top-level = 16 item (sebelumnya 13).

- [2026-10-01 08:05] **BUG: `--selftest` crash exit 133 — Carbon key code bukan rentang**
  - Symptom: `selftest` mati dengan SIGTRAP (exit 133), stdout kosong, 0 byte.
  - Root cause: `HotKeyConflict` bikin range `kVK_F1...kVK_F12`. Code F-key Carbon **tidak monotonik**: F1=122, F2=120, F12=111, F20=90. Swift `Range` butuh lowerBound <= upperBound → trap saat range itu Dibuat, bukan saat dipakai.
  - Damage lebih luas dari yang kelihatan: `keyName` punya 3 range salah — `kVK_ANSI_A...kVK_ANSI_Z` (=0...6, jadi cuma 7 dari 26 huruf ke-cover dan letter mapping ngawur), `kVK_ANSI_0...kVK_ANSI_9` (29...25, terbalik), `kVK_F1...kVK_F20` (122...90, terbalik). Yang survived cuma karena crash duluan di F-key.
  - Fix: table eksplisit untuk semua key code (huruf, digit, F1-F20, navigasi, punctuation) + `Set<UInt32>` untuk F1-F12. Nol range di seluruh file.
  - Verified: 5/5 `glyph` lines ok (⌘⌥0, ⌘⌥1, ⌘⌥2, ⌘⌥3, ⌥Esc) — ini satu-satunya bukti table-nya lengkap.

- [2026-10-01 08:05] **BUG: `describe()` urut modifier ≠ yang di menu**
  - `describe` bikin ⌃⌥⇧⌘ (urutan Apple) tapi menu/spec ngajarin ⌘⌥1. Recorder bakal nampilin "⌥⌘2" buat binding yang user tau sebagai "⌘⌥2".
  - Fix: urut ⌘⌥⇧⌃, sama dengan menu dan spec.

- [2026-10-01 08:05] **BUG: pixel check spuriously FAIL di install yang sudah ditune user**
  - Symptom: `--selftest` dari `/Applications` FAIL, dari `.build/out` PASS. Build sama persis.
  - Root cause: `checkSpotlight`/`checkSpotlightEdge` ngitung luminance dari render yg baca `Settings.shared`. Install ini punya `spotlightDim = 0.76` → surround = 61, satu step di atas bound `< 60`. Jadi suite gagal bukan karena ada bug, tapi karena user menune slidnya.
  - Ini chasing-the-wrong-thing yang klasik: bounds pixel di premise "arithmetic, bukan judgement call" (komentar di file itu sendiri), tapi premise-nya dilanggar dari luar.
  - Fix: `PinnedLook` — pin `spotlightDim` + `spotlightRadius` ke `Settings.Default` selama pixel check, restore setelahnya. Nilai yang di-restore = nilai yang dipin, jadi state on-disk tidak berubah.
  - Verified: `defaults read` `spotlightDim` = 0.76 sebelum DAN sesudah run. exit 0.

- [2026-10-01 08:05] **Catatan: `main.swift` harus baca binding dari Settings, bukan Defaults**
  - Plan Task 7 hanya menyuruh pasang menu item. Tapi kalau `handleHotKeyPress` baca `HotKeyBinding.Defaults.bindings` sementara registrasi Carbon baca tabel live, maka rebind yang sudah disimpan tidak pernah dipakai — hotkey yang aktif ≠ yang tampil di recorder.
  - Fix: satu accessor `bindings()` → `Settings.shared.hotKeyBindings`, dipakai oleh registrasi awal, `mode(for:)`, dan commit recorder.
  -Jugur masalah:`resetSettings` juga harus re-register, karena `Settings.reset()` sekarang ikut restore binding table. Kalau tidak, table dan hotkey yang hidup beda sampai relaunch.

- [2026-10-01 08:05] **Belum terverifikasi butuh tangan + keyboard asli**
  - Hold vs toggle behaviour saat key benar-benar ditekan (threshold 0.25s proven di unit test, tapi bukan dari event Carbon nyata).
  - Recorder: window benar-benar dapat first responder, `Set…` → "Press keys…" → accept/reject.
  - `⌘⌥1` saat recorder terbuka: tidak boleh trigger Spotlight (ini yang diuji `hotkeys?.stop()`).
  - Conflict message muncul di status label dan previous binding bertahan.
  - Closing dengan tombol title bar harus commit (saya jadikan commit, bukan discard — panel tidak punya jalan save lain; konfirmasi dulu kalau ini undesirable).

- [2026-10-01 08:40] **BUG: panel Shortcuts terbuka tapi isinya nggak bisa diklik — DUA cause, dua-duanya layout**
  - Symptom: user report "popup shortcut ketika terbuka tidak bisa di pilih". Panel kebuka, keliatan normal, tapi nggak ada yang bisa diklik.
  - **Cause 1 — `translatesAutoresizingMaskIntoConstraints` nggak di-set di subview row.**
    `Row.init` set flag itu di `Row` itu sendiri, tapi TIDAK di `name`/`value`/`mode`/`button`. Akibatnya semua constraint yang di-activate di `Row.init` jadi INERT, dan keempat control cuma dapat frame 0×0 di origin row. Nol area = nol yang bisa diklik. Ini cause utama.
  - **Cause 2 — recorder telanjur ada di atas.** Recorder di-add terakhir (line 213) dengan constraint nempel ke SELURUH content rect, jadi AppKit (yang hit-test subview dalam urutan reverse-add) nempatin dia di atas semua control. `NSView` polos nggak auto-return `nil` dari `hitTest`, jadi dia menelan SEMUA klik.
    Fix: `override func hitTest(_:) -> NSView? { nil }` → mouse transparan, tapi `makeFirstResponder` tetap jalan (itu syarat utama recorder).
  - Verifikasi geometri (bukan cuma "selftest PASS"): semua row button=(298, y, 52×20), mode=(210, y, 78×20). Rowan yang mode-nya hidden (All Off) TETAP dapat button 52×20 karena cause-1 fix membuat constraints-nya hidup.
  - Test yang membuktikan: `checkRecorderHitTesting` — order window front, paksa layout, lalu `contentView.hitTest()` di titik yang benar-benar diklik user.
  - **Pelajaran (penting, dua-duanya):**
    1. Layout constraint yang salah-satu participant-nya lupa `translatesAutoresizingMaskIntoConstraints = false` **tidak error, tidak warning, tidak crash**. Constraint-nya hidup, satisfying, dan tidak melakukan apa pun. Ini silent failure yang paling mahal di Auto Layout.
    2. `NSView.hitTest` return `nil` kalau view-nya belum di-ordered window — artinya test hit-test yang nggak `orderFront` dulu akan FALSE-PASS untuk panel apa pun. Test pertama saya salah baca karena ini, dan hampir "konfirmasi" hipotesis yang salah. Fix test-nya, bukan hipotesisnya.
  - Catatan: `mode.isHidden` untuk row panic — AppKit auto-deactivate constraint yang nyentuh hidden view, tapi karena `button.leading = mode.trailing` dan mode cuma hidden di row itu, ternyata tetap resolve. Dicek eksplisit lewat geometri, bukan diasumsikan aman.

- [2026-10-01 08:55] **Default shortcut diubah: ⌘⌥0-3 → ⌥0-3 (⌘ dihapus)**
  - Request user: "rubah default shortcut menjadi opt + 1,2,3,0 tidak usah cmd".
  - `HotKeyBinding.Defaults.cmdOpt` → `Defaults.opt` (cuma `optionKey`). Key code tetap: `1D:0` (off), `12:1` (spotlight), `13:2` (laser), `14:3` (zoom), `35:Esc` (panic).
  - Konflik rules TIDAK dilonggarkan: `HotKeyConflict` tetap wajib ⌘ ATAU ⌥ untuk effect. Jadi relaxing default ini cuma mengubah apa yang di-*ship*, bukan batas validasi. Bare key tetap ditolak.
  - Konsekuensi yang harusCBCATAT: `checkConflictRules` punya kasus "duplicate of spotlight" yang hardcode `cmdOpt+1`. Kalau cuma ganti default tanpa ganti kasus ini, test jadi Menolak → test MEMANG kepakai untuk menjaga invariant, bukan noise. Dua kasus lain (`persist` want-string, glyph map) juga跟着.
  - Verified: `binding No Effect: 1D:opt`, `Spotlight: 12:opt`, `Laser: 13:opt`, `Zoom: 14:opt`, `All Off: 35:opt`; glyph `⌥0 ⌥1 ⌥2 ⌥3 ⌥Esc`; 5/5 register ok; selftest PASS exit 0 dari `/Applications`.
  - **PENTING — install punya binding TERSIMPAN, jadi default baru BELUM berlaku untuk user ini:**
    `~/Library/Preferences/id.my.digitechnesia.presentools.plist` punya 10 key `hotkey.*` (mtime 08:00) — spotlight=`2048` (opt saja, mode toggle!), laser=`2304` (cmd+opt), zoom=`2304`, none=`2304`. Jadi user ini sudah pernah set manual via recorder (spotlight sudah opt+toggle), dan sisanya masih cmd+opt dari sebelum.
    Persisted table menang atas `Defaults` — itu perilaku yang BENAR (user override harus menang). Efeknya: app yang baru deploy masih jalan dengan ⌘⌥ untuk laser/zoom/off sampai di-reset.
  - Next: user pilih — biarkan (hammer lama masih jalan), atau reset via menu "Reset to Defaults" untuk mengambil default baru. TIDAK saya hapus diam-diam karena itu menghapus pilihan yang mungkin memang disengaja.
  - Angka modifier: cmdKey=256 (0x100), optionKey=2048 (0x800). cmd+opt=2304. Dipakai buat baca `defaults read` output.
