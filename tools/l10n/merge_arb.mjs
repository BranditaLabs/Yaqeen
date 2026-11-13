#!/usr/bin/env node
// Merges two versions of an ARB file (apps/mobile/lib/l10n/app_{ar,en}.arb) without conflict
// markers: the union of keys, each value from the side that changed it, prefix blocks kept in order.
//
// CONTRIBUTING (design docs/design/2026-11-profile-community-quran.md §14):
//   - The contracts stream added every key up front, in one contiguous block per prefix
//     (av, div, badge, lvl, pf, cm, hm, ob, qs, sk). Streams change only the values of their own
//     prefix; a truly new key is appended inside its prefix block.
//   - On a merge/rebase conflict in an ARB file, run from the repo root:
//         node tools/l10n/merge_arb.mjs                 # resolves both ARB files from the git index
//     or, as a three-way merge of explicit files (also usable as a git merge driver: %O %A %B):
//         node tools/l10n/merge_arb.mjs <base> <ours> <theirs> [--out <file>]   # default out: <ours>
//     then `git add` the files and run `flutter gen-l10n`.
//   - Rules: a key on one side only is kept (inserted after its nearest preceding key from that
//     side, so it lands inside its prefix block); a value changed on one side only wins; changed on
//     both sides differently → ours is kept and the key is reported (exit code 2) for a human look;
//     a key deleted on one side and untouched on the other is deleted. `@key` metadata travels with
//     its key. Output: 2-space JSON, UTF-8, trailing newline (as tools/l10n/arb.py writes).
import { execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync } from 'node:fs';

const isMeta = (k) => k.startsWith('@') && !k.startsWith('@@');
const baseKey = (k) => (isMeta(k) ? k.slice(1) : k);

/** Groups `key` and `@key` into entries, in file order. */
function entries(obj) {
  const order = [];
  const map = new Map();
  for (const [k, v] of Object.entries(obj)) {
    const id = baseKey(k);
    if (!map.has(id)) {
      map.set(id, {});
      order.push(id);
    }
    map.get(id)[k] = v;
  }
  return { order, map };
}

const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);

export function mergeArb(base, ours, theirs) {
  const b = entries(base ?? {});
  const o = entries(ours);
  const t = entries(theirs);
  const conflicts = [];
  const order = [...o.order];
  const out = new Map();

  for (const id of o.order) {
    const ov = o.map.get(id);
    const tv = t.map.get(id);
    const bv = b.map.get(id);
    if (tv === undefined) {
      // Deleted on their side and untouched on ours → delete; else keep ours.
      if (bv !== undefined && same(bv, ov)) continue;
      out.set(id, ov);
    } else if (same(ov, tv)) {
      out.set(id, ov);
    } else if (bv !== undefined && same(ov, bv)) {
      out.set(id, tv); // only they changed it
    } else if (bv !== undefined && same(tv, bv)) {
      out.set(id, ov); // only we changed it
    } else {
      conflicts.push(id);
      out.set(id, ov);
    }
  }

  // Their new keys: insert after the nearest preceding key (in their order) that we kept.
  for (let i = 0; i < t.order.length; i++) {
    const id = t.order[i];
    if (o.map.has(id)) continue;
    const bv = b.map.get(id);
    if (bv !== undefined && same(bv, t.map.get(id))) continue; // we deleted it, they didn't touch it
    let at = -1;
    for (let j = i - 1; j >= 0; j--) {
      const prev = order.indexOf(t.order[j]);
      if (prev >= 0) {
        at = prev;
        break;
      }
    }
    order.splice(at + 1, 0, id);
    out.set(id, t.map.get(id));
  }

  const merged = {};
  for (const id of order) {
    const e = out.get(id);
    if (!e) continue;
    if (id in e) merged[id] = e[id];
    for (const [k, v] of Object.entries(e)) if (k !== id) merged[k] = v;
  }
  return { merged, conflicts };
}

const parse = (text) => JSON.parse(text.replace(/^﻿/, ''));
const serialize = (obj) => `${JSON.stringify(obj, null, 2)}\n`;

function fromIndex(path, stage) {
  try {
    return parse(execFileSync('git', ['show', `:${stage}:${path}`], { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 }));
  } catch {
    return null;
  }
}

function main(argv) {
  let exit = 0;
  const report = (file, conflicts) => {
    if (conflicts.length) {
      exit = 2;
      console.error(`${file}: changed differently on both sides, kept ours: ${conflicts.join(', ')}`);
    }
    console.log(`merged ${file}`);
  };
  const files = argv.filter((a) => !a.startsWith('--'));
  if (files.length >= 3) {
    const [basePath, oursPath, theirsPath] = files;
    const outIdx = argv.indexOf('--out');
    const outPath = outIdx >= 0 ? argv[outIdx + 1] : oursPath;
    let base = null;
    try {
      base = parse(readFileSync(basePath, 'utf8'));
    } catch {
      base = null;
    }
    const { merged, conflicts } = mergeArb(base, parse(readFileSync(oursPath, 'utf8')), parse(readFileSync(theirsPath, 'utf8')));
    writeFileSync(outPath, serialize(merged));
    report(outPath, conflicts);
    return exit;
  }
  for (const path of ['apps/mobile/lib/l10n/app_ar.arb', 'apps/mobile/lib/l10n/app_en.arb']) {
    const ours = fromIndex(path, 2);
    const theirs = fromIndex(path, 3);
    if (!ours || !theirs) {
      console.log(`${path}: not in conflict`);
      continue;
    }
    const { merged, conflicts } = mergeArb(fromIndex(path, 1), ours, theirs);
    writeFileSync(path, serialize(merged));
    report(path, conflicts);
  }
  return exit;
}

if (import.meta.url === `file://${process.argv[1]}` || process.argv[1]?.endsWith('merge_arb.mjs')) {
  process.exit(main(process.argv.slice(2)));
}
