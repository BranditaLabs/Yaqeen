# Content packs on Cloudflare R2

Large offline packs (the tafsir first; spec §6.6, §10) are served from **Cloudflare R2** behind
Cloudflare's CDN. R2 has no egress fees, so download cost doesn't grow with traffic.
- The API only lists a pack (`GET /v1/content/packs`).
- The app downloads it straight from R2 (resumable, using HTTP Range) and checks its sha256 before
  installing it.

Objects are **content-addressed and immutable**, for example
`packs/tafsir/tafsir-arabic_moyassar-<sha12>.json` with `Cache-Control: immutable`. A new source
version is a new object, so the CDN never serves a stale file and older apps keep working.

## One-time setup (≈10 min)
1. **Cloudflare dashboard › R2** → enable R2 → **Create bucket** `yaqeen-packs` (location: Automatic).
2. Bucket › **Settings › Custom Domains** → **Connect domain** `cdn.yaqin-brand.com`.
   - The zone must be on Cloudflare.
   - This puts the bucket behind the CDN cache. The `r2.dev` URL is rate-limited: don't ship it.
3. **R2 › Manage API tokens** → **Create API token**:
   - permission *Object Read & Write*, scoped to `yaqeen-packs` only;
   - note the Access Key ID, the Secret Access Key and your Account ID.
4. GitHub → **Settings › Secrets and variables › Actions**:

| Name | Kind | Value |
| --- | --- | --- |
| `R2_ACCOUNT_ID` | secret | Cloudflare account ID |
| `R2_ACCESS_KEY_ID` | secret | token's Access Key ID |
| `R2_SECRET_ACCESS_KEY` | secret | token's Secret Access Key |
| `R2_BUCKET` | variable | `yaqeen-packs` |
| `PACKS_PUBLIC_BASE_URL` | variable | `https://cdn.yaqin-brand.com` |

## Publishing the tafsir
1. **Actions › Tafsir pack › Run workflow**. The run:
   - builds التفسير الميسر from QuranEnc.com, unaltered;
   - checks all 6,236 ayat;
   - uploads the pack to R2 and confirms the public URL serves the same bytes.
2. Copy the `TAFSIR_PACK_*` lines from the run summary into the API's environment:
   - bump `TAFSIR_PACK_VERSION` (an integer) each time;
   - then run `pnpm db:seed`.
3. On its next weekly pack check, each app offers the new version.

Without the R2 settings the workflow still builds and verifies the pack. It then keeps the pack only
as a run artifact and prints a warning.

QuranEnc's terms apply to the hosted file: no edits, credit QuranEnc.com, state the version, and
follow their latest version. `tools/tafsir/build_pack.py` lists them.
