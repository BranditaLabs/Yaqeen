import assert from 'node:assert/strict';
import { test } from 'node:test';
import { isUuid } from './ids.ts';
import { COMPETITION_ERROR } from './labels.ts';

test('COMPETITION_ERROR uses the API codes: a ZodError answers validation_failed', () => {
  assert.equal(COMPETITION_ERROR.validation_failed, 'تحقق من الحقول');
  assert.equal(COMPETITION_ERROR.validation, undefined);
  assert.ok(COMPETITION_ERROR.account_inactive);
});

test('isUuid: only a canonical UUID reaches the API', () => {
  assert.equal(isUuid('0b0e6a3c-0000-4000-8000-000000000000'), true);
  assert.equal(isUuid('abc'), false);
  assert.equal(isUuid('0b0e6a3c-0000-4000-8000-000000000000x'), false);
});
