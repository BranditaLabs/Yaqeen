# Content sources — azkar and duas

Owner decision (2026-11-10): azkar and duas are imported **verbatim from an authenticated published
source we hold written permission for**, each item with its source reference; the source is the
approval (CLAUDE.md non-negotiable 4). Nothing is written in-house.

## Status

**No source is licensed yet — the app ships with no azkar/duas until permission is granted.**
Researched 2026-11-10 (licence pages and data samples checked first-hand):

| Source | Verdict |
| --- | --- |
| «حصن المسلم من أذكار الكتاب والسنة», Dr. Sa'id bin Ali bin Wahf al-Qahtani (rahimahullah) — the estate's edition | **Chosen.** All rights reserved (binwahaf.com); printed copies may only be redistributed whole and unchanged → needs written permission |
| IslamHouse Arabic DOCX (`d1.islamhouse.com/data/ar/ih_books/single_01/ar_Hisn_Almuslim.docx`) | Best machine-readable copy (verbatim, fully vowelled, takhrij as footnotes) — usable only if the permission covers it |
| Risala / General Presidency English edition | Separate licence needed for the English |
| hisnmuslim.com API, GitHub JSON copies, Darussalam, code repos (MIT/GPL) | Not usable: no licence for the text, errors, or all rights reserved |

## Models (not content)

The «تلاواتي» speech check (`services/asr`) uses a speech-recognition **model**, not religious content: it only transcribes a user's own recording so the API can compare it with the verses they chose. It publishes nothing.

| Model | Licence | Revision | Where |
| --- | --- | --- | --- |
| [`tarteel-ai/whisper-base-ar-quran`](https://huggingface.co/tarteel-ai/whisper-base-ar-quran) (Whisper base fine-tuned on Quran recitation) | Apache-2.0 (model card, checked 2026-11-14); base `openai/whisper-base` | `5c3c53fdf9272c4f6ee0bee09a1e5a4a615ee25c` | converted to CTranslate2 int8 at image build (`services/asr/Dockerfile`) |

The matcher's expected words (`services/api/data/quran-words.txt`) are normalised matching keys generated from the app's bundled mushaf text (`apps/mobile/assets/quran/quran.json`, same source and attribution as the app) by `services/api/scripts/build-quran-words.ts`; they are never displayed.

## Permission request

Send to the author's office through **Arabia for Information Technology** (publisher of the official
«حصن المسلم» app, App Store id1439791907 — use the developer contact on the listing / their site
hisn-almuslim.com), and the English to Risala / IslamHouse (en@islamhouse.com):

> السلام عليكم ورحمة الله وبركاته،
>
> نحن فريق تطبيق «يقين»، تطبيق إسلامي مجاني في مصر (تديره شركة لها متجر إلكتروني). نرغب في عرض أذكار
> وأدعية كتاب «حصن المسلم من أذكار الكتاب والسنة» للشيخ د. سعيد بن علي بن وهف القحطاني رحمه الله داخل
> التطبيق، بنصّها الحرفي دون أي حذف أو إضافة أو تغيير، مع تخريج كل ذكر كما في الكتاب، ونسبة الكتاب
> ومؤلفه بوضوح في كل شاشة، ودون بيع المحتوى أو تقاضي أي مقابل عليه.
>
> نرجو التكرّم بما يلي:
> 1. إذن كتابي غير حصري لهذا الاستخدام الرقمي (والترجمة الإنجليزية إن كانت حقوقها لديكم).
> 2. تحديد الطبعة المعتمدة، والصيغة المطلوبة لنسبة الكتاب.
> 3. تزويدنا بالملف الرقمي المعتمد إن أمكن، أو الإذن باستخدام نسخة موقع دار الإسلام (IslamHouse).
> 4. تأكيد صفة من يوقّع الإذن نيابةً عن الورثة.
>
> وجزاكم الله خيراً.
> [الاسم — الصفة — الشركة — البريد — الهاتف]

## When permission arrives

1. Save the grant (PDF/email) with the company's records; note the edition and attribution wording here.
2. Tell the engineering team the permitted file → the importer parses it verbatim (chapter → category
   `azkar` for recurring daily chapters, `duas` for occasions; repeat count from the text; footnote
   takhrij as `reference`; Quran passages rendered from our licensed Quran text by `surah:ayah`),
   pins its checksum, and publishes with the source recorded as the approval.
3. Show the attribution the grant requires in «عن يقين» and on each content screen.
