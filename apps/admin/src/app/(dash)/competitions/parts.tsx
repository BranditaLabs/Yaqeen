import Link from 'next/link';
import { LEVELS, type AdminCompetitorRow, type AdminStandingRow } from '@yaqeen/contracts';
import { CompetitorActions } from '@/components/competitor-actions';
import { Avatar, Badge, LevelRing, Table, Td } from '@/components/ui';
import { dateTime, num } from '@/lib/format';

export const HIDDEN_NAME = 'عضو يقين';
export const levelName = (level: number) => LEVELS[level - 1]?.ar ?? '';

/**
 * Shared copy under every standings list (design §1.4). `day`: the snapshot day, null when none was
 * taken yet, undefined when the endpoint does not say (the line then names no day). `final`: the
 * results of a closed period, which come from its close, not from a nightly snapshot.
 */
export function SnapshotLine({ day, final = false }: { day?: string | null; final?: boolean }) {
  if (final) return <p className="mt-3 text-xs text-muted">النتائج النهائية عند الإغلاق</p>;
  return (
    <p className="mt-3 text-xs text-muted">
      يُحدَّث الترتيب كل ليلة
      {day ? (
        <>
          {' '}· آخر لقطة <span className="num">{day}</span>
        </>
      ) : day === null ? (
        ' · لم تُلتقط بعد'
      ) : null}
    </p>
  );
}

/** Rank cell: «—» without a rank; gold only for ranks 1–3 once the period closed (an achievement). */
function Rank({ rank, podium }: { rank: number | null; podium: boolean }) {
  if (rank === null) return <span className="text-muted">—</span>;
  if (podium && rank <= 3) {
    return <span className="num inline-grid h-7 min-w-7 place-items-center rounded-full bg-sand px-2 text-sm font-semibold text-gold-text">{num(rank)}</span>;
  }
  return <span className="num text-sm text-ink">{num(rank)}</span>;
}

/**
 * Snapshot standings (rank, avatar, name/@handle, level, period points) — never worship detail.
 * Points 0 or not yet snapshotted show «—». Support/super get a per-row «إجراء» with the
 * moderation forms.
 */
export function StandingsTable({
  rows,
  points = true,
  podium = false,
  canModerate = false,
  extra,
}: {
  rows: (AdminStandingRow & { outcome?: string | null })[];
  points?: boolean;
  podium?: boolean;
  canModerate?: boolean;
  extra?: { head: string; cell: (r: AdminStandingRow & { outcome?: string | null }) => React.ReactNode };
}) {
  const head = ['المركز', 'المشارك', 'المستوى', ...(points ? ['النقاط'] : []), ...(extra ? [extra.head] : []), ...(canModerate ? ['إجراء'] : [])];
  return (
    <Table head={head}>
      {rows.map((r) => (
        <tr key={r.userId}>
          <Td className="w-16">
            <Rank rank={r.rank} podium={podium} />
          </Td>
          <Td>
            <div className="flex items-center gap-3">
              <Avatar avatar={r.avatar} name={r.name ?? HIDDEN_NAME} size={32} />
              <div className="min-w-0">
                <Link href={`/users/${r.userId}`} className="block truncate font-medium text-ink hover:text-lapis">
                  {r.name ?? <span className="text-muted">{HIDDEN_NAME}</span>}
                </Link>
                <p dir="ltr" className="num truncate text-right text-xs text-muted">
                  @{r.handle}
                </p>
              </div>
            </div>
          </Td>
          <Td>
            <div className="flex items-center gap-2">
              <LevelRing level={r.level.level} progress={r.level.progress} label={`المستوى ${r.level.level}: ${levelName(r.level.level)}`} />
              <span className="text-xs text-muted">{levelName(r.level.level)}</span>
            </div>
          </Td>
          {points && <Td className="num">{r.points ? num(r.points) : <span className="text-muted">—</span>}</Td>}
          {extra && <Td>{extra.cell(r)}</Td>}
          {canModerate && (
            <Td>
              <details>
                <summary className="cursor-pointer text-sm text-lapis">إجراء</summary>
                <div className="mt-2 space-y-2">
                  {/* A standings row is the public projection: a null name may be one never set, and
                      bans or restorable photos are not in it. Offer only the hides it can tell apart;
                      everything else lives on the user page with the full competitor row. */}
                  <CompetitorActions
                    compact
                    actions={[...(r.name !== null ? (['hide-name'] as const) : []), ...(r.avatar.kind === 'photo' ? (['hide-photo'] as const) : [])]}
                    state={{ userId: r.userId, nameHidden: r.name === null, photoActive: r.avatar.kind === 'photo', photoRestorable: false, banned: false }}
                  />
                  <Link href={`/users/${r.userId}`} className="inline-flex min-h-10 items-center text-sm text-lapis">
                    كل الإجراءات في صفحة المستخدم
                  </Link>
                </div>
              </details>
            </Td>
          )}
        </tr>
      ))}
    </Table>
  );
}

/** Gold medal art for the badge catalogue (gold = achievement). */
export function Medal({ size = 44 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 44 44" aria-hidden className="shrink-0">
      <path d="M14 3h6l3 10h-6zM30 3h-6l-3 10h6z" fill="var(--yq-goldLight)" />
      <circle cx="22" cy="27" r="13" fill="var(--yq-sand)" stroke="var(--yq-gold)" strokeWidth="2" />
      <circle cx="22" cy="27" r="8.5" fill="var(--yq-goldLight)" stroke="var(--yq-gold)" strokeWidth="1.2" />
    </svg>
  );
}

/* ------------------------------------------------------------- moderation */

const PHOTO_STATUS = { active: 'الحالية', replaced: 'مُستبدلة', removed: 'محذوفة' } as const;

export function competitorState(c: AdminCompetitorRow) {
  return {
    userId: c.userId,
    nameHidden: c.nameHidden,
    photoActive: c.avatar.kind === 'photo' && !c.photoHidden,
    photoRestorable: c.photos.some((p) => p.status === 'removed' && p.removedBySupport),
    banned: c.banned,
  };
}

/** Name, handle and moderation flags of one competitor (shared by the queue and the user page). */
export function CompetitorFlags({ c }: { c: AdminCompetitorRow }) {
  return (
    <div className="flex flex-wrap gap-1.5">
      {c.nameHidden && <Badge tone="red">الاسم مخفي</Badge>}
      {c.photoHidden && <Badge tone="red">الصورة مخفية</Badge>}
      {c.banned && <Badge tone="red">موقوف من المنافسات</Badge>}
      <Badge tone={c.attestedAdult ? 'blue' : 'gray'}>أكّد العمر: {c.attestedAdult ? 'نعم' : 'لا'}</Badge>
      {c.leagues && <Badge tone="blue">الدوري</Badge>}
      {c.leaderboard && <Badge tone="blue">لوحة المستويات</Badge>}
      {c.leaderboardCountry && <Badge tone="blue">لوحة الدولة</Badge>}
      {c.openReports > 0 && (
        <Badge tone="red">
          بلاغات مفتوحة: <span className="num ms-1">{num(c.openReports)}</span>
        </Badge>
      )}
    </div>
  );
}

/** Photo history (any status within 7 days) through the admin proxy — support and super admin only. */
export function PhotoHistory({ c }: { c: AdminCompetitorRow }) {
  if (c.photos.length === 0) return <p className="text-xs text-muted">لا صور خلال 7 أيام</p>;
  return (
    <ul className="flex flex-wrap gap-3" aria-label="سجل الصور">
      {c.photos.map((p) => (
        <li key={p.id} className="text-center">
          {/* eslint-disable-next-line @next/next/no-img-element -- private, uncached photo via the admin proxy */}
          <img
            src={`/api/competitors/${c.userId}/photos/${p.id}/96`}
            alt={`صورة ${PHOTO_STATUS[p.status]} · ${dateTime(p.createdAt)}`}
            width={56}
            height={56}
            loading="lazy"
            data-photo-status={p.status}
            className={`h-14 w-14 rounded-tile border object-cover ${p.status === 'active' ? 'border-lapis' : 'border-line opacity-80'}`}
          />
          <p className="mt-1 text-[11px] text-muted">
            {PHOTO_STATUS[p.status]}
            {p.status === 'removed' && (p.removedBySupport ? ' · الدعم' : ' · صاحبها')}
          </p>
        </li>
      ))}
    </ul>
  );
}
