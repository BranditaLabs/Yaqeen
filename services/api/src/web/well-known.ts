/**
 * Universal links / App Links verification files (spec §6.20), served by the API on the site host so
 * `https://<site>/app/<target>` opens the app. Built from configuration; `null` = not configured
 * (the route answers 404 — never a file with placeholder ids).
 */

/** Paths the app handles; everything else on the site stays in the browser. */
const APP_PATHS = '/app/*';

export function appleAppSiteAssociation(teamId: string, bundleId: string): object | null {
  if (!/^[A-Z0-9]{10}$/.test(teamId)) return null;
  const appId = `${teamId}.${bundleId}`;
  return {
    applinks: {
      details: [{ appIDs: [appId], components: [{ '/': APP_PATHS, comment: '<site>/app/<target> → routeForDeepLink' }] }],
    },
    webcredentials: { apps: [appId] },
  };
}

/** `fingerprints`: SHA-256 of every signing key that ships the app (Play app signing, upload, debug). */
export function assetLinks(packageName: string, fingerprints: string[]): object[] | null {
  const valid = fingerprints.map((f) => f.toUpperCase()).filter((f) => /^([0-9A-F]{2}:){31}[0-9A-F]{2}$/.test(f));
  if (valid.length === 0) return null;
  return [
    {
      relation: ['delegate_permission/common.handle_all_urls'],
      target: { namespace: 'android_app', package_name: packageName, sha256_cert_fingerprints: valid },
    },
  ];
}
