# Brand fonts — licensed files go here

The brand guide specifies two commercial typefaces. They are **not** in the repo until licences are confirmed:

| Typeface | Use | Files expected | Licence needed |
| --- | --- | --- | --- |
| ZEYADA Arabic 1 (Regular, Medium, Bold) | Arabic headlines, brand moments | `ZeyadaArabic-Regular.ttf`, `-Medium.ttf`, `-Bold.ttf` | Desktop + **app embedding** + web |
| Canela Text (Regular, Medium, Bold) | Latin headlines | `CanelaText-Regular.otf`, `-Medium.otf`, `-Bold.otf` | Commercial Type: desktop + **app** + web |

Until the files are here, the apps fall back to Amiri / Tajawal (Arabic) and Amiri / Georgia (Latin).
The logo never depends on fonts — it is always the PNG artwork in `../logo`.

When the files arrive:
1. Copy them into `apps/mobile/assets/fonts/` and un-comment the two families in `apps/mobile/pubspec.yaml`.
2. Copy the `.woff2` versions into `apps/admin/public/fonts/` (the `@font-face` rules in `globals.css` already point there).
