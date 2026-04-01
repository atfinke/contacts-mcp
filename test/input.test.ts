import test from "node:test";
import assert from "node:assert/strict";

import {
  normalizeContactIdentifier,
  normalizeEmailLookupInput,
  normalizePhoneLookupInput,
} from "../src/input.js";

test("normalizePhoneLookupInput strips supported handle schemes", () => {
  assert.equal(normalizePhoneLookupInput(" tel:+1 (312) 555-0100 "), "+1 (312) 555-0100");
  assert.equal(normalizePhoneLookupInput("sms:3125550100"), "3125550100");
});

test("normalizePhoneLookupInput rejects empty values", () => {
  assert.throws(() => normalizePhoneLookupInput("   "), /Provide a phoneNumber/u);
  assert.throws(() => normalizePhoneLookupInput("tel: "), /Provide a phoneNumber/u);
});

test("normalizeEmailLookupInput strips mailto and lowercases", () => {
  assert.equal(normalizeEmailLookupInput(" MAILTO:Person@Example.COM "), "person@example.com");
});

test("normalizeEmailLookupInput rejects empty values", () => {
  assert.throws(() => normalizeEmailLookupInput(" "), /Provide an emailAddress/u);
  assert.throws(() => normalizeEmailLookupInput("mailto: "), /Provide an emailAddress/u);
});

test("normalizeContactIdentifier trims and validates", () => {
  assert.equal(normalizeContactIdentifier("  ABC-123  "), "ABC-123");
  assert.throws(() => normalizeContactIdentifier(" "), /Provide a contactIdentifier/u);
});
