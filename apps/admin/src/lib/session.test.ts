import assert from 'node:assert/strict';
import { test } from 'node:test';
import { NAV_ACCESS, sectionOf } from './session.ts';

test('sectionOf: the longest NAV_ACCESS prefix on a path boundary, never the overview', () => {
  assert.equal(sectionOf('/'), null);
  assert.equal(sectionOf('/login'), null);
  assert.equal(sectionOf('/competitions'), '/competitions');
  assert.equal(sectionOf('/competitions/tournaments/new'), '/competitions');
  assert.equal(sectionOf('/competitions/leagues/groups/0b0e6a3c-0000-4000-8000-000000000000'), '/competitions');
  assert.equal(sectionOf('/users/abc'), '/users');
  // A prefix that is not a path segment is a different path.
  assert.equal(sectionOf('/competitionsx'), null);
  assert.equal(sectionOf('/cardsets'), null);
});

test('«المسابقات» is for super admin, marketing and support only', () => {
  assert.deepEqual([...NAV_ACCESS['/competitions']!].sort(), ['marketing', 'super_admin', 'support']);
});
