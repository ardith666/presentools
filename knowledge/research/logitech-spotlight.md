---
url: https://www.logitech.com/id-id/shop/p/spotlight-presentation-remote.910-004864
fetched: 2026-09-30
summary: Halaman produk Logitech Spotlight presentation remote — cuma marketing blurb, tidak berisi spesifikasi teknis fitur spotlight/zoom/laser.
---

# Logitech Spotlight Presentation Remote (910-004864)

**Status: sumber tidak terverifikasi.** Halaman yang berhasil di-fetch hanya berisi deskripsi marketing. Klaim teknis fitur (spotlight effect, virtual zoom ~5x, range vibration, gesture) **tidak ada** di sumber ini — asalnya dari ingatan, bukan dari fetch.

## Yang benar-benar ada di sumber

- Jangkauan maksimum 30 m
- Bluetooth dan USB
- "Penunjuk digital untuk layar"
- Harga Indonesia: Rp 2.199.000
- Kategori: `public.app-category.music` (dari device, tidak relevan)
- Deskripsi qualitative: "remote presentasi yang mengubah permainan", "melampaui laser penunjuk tradisional", "penunjuk yang bekerja secara langsung, secara virtual, atau gabungan keduanya"

## Fetch yang gagal

| URL | Hasil |
|---|---|
| `logitech.com/id-id/shop/p/spotlight-...910-004864` | OK, tapi hanya marketing blurb |
| `logitech.com/en-us/products/keyboards/spotlight/presentation-remote.html` | Redirect ke `/shop`, respons terpotong |
| `support.logitech.com/en-us/articles/360025245354` | Too many redirects (limit 3) |
| `support.logitech.com/en-us/article/smart-shift-zoom-in-out-spotlight` | Too many redirects (limit 3) |

`web_search` juga **disabled** di environment ini, jadi tidak ada jalur cari sekunder.

## Konsekuensi ke scope

Klaim yang **tidak** terverifikasi dan tidak boleh dipakai sebagai fakta:

- Magnifikasi zoom ~5x
- "Tele-prompter" — apakah itu feature nyata atau nama marketing
- Range vibration (keyboard bergetar saat cursor menyentuh layar) — kemungkinan besar **fitur hardware**, tidak ada di software
- Gesture swipe di remote untuk next/prev slide — kemungkinan besar **fitur hardware** (sensor), tidak ada di software
- Penanda faint yang terkirim ke audiens virtual via alpha channel video — **belum jelas apakah mungkin**, sangat mahal

Yang **aman** dipakai untuk scope: 3 efek software yang disebut eksplisit di halaman produk — "berfungsi secara langsung, secara virtual, atau gabungan" + "penunjuk digital". Ini cukup untuk v1, dan memang itu yang diminta user.

## Open Questions

- [ ] Berapa magnifikasi zoom yang sebenarnya? Kalau user tidak peduli angka, pakai angka yang terasa nyaman — tidak perlu riset
- [ ] Apakah ada bedanya meaningful antara mode "laser legacy" (ada jejak, fades) dan "digital pointer" (persisten)? User tidak menyebut, v1 cukup satu mode persisten
- [ ] Perlu tidak sih fitur hardware Logitech dicatat di README sebagai "beyond software", atau cukup diamkan

## Related

[[KNOWLEDGE]] · [[macos-27-overlay]]
