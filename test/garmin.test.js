import test from "node:test";
import assert from "node:assert/strict";
import { unzip } from "../src/garmin.js";
import { makeZip } from "./fixtures/make-zip.js";
import { makeFit } from "./fixtures/make-fit.js";
import { isFit } from "../src/parsers/fit.js";

test("unzip returns a deflated entry byte for byte", async () => {
  const fit = makeFit();
  const entries = await unzip(makeZip("111_ACTIVITY.fit", fit));
  assert.equal(entries.length, 1);
  assert.equal(entries[0].name, "111_ACTIVITY.fit");
  assert.ok(isFit(entries[0].bytes));
  assert.deepEqual(Buffer.from(entries[0].bytes), Buffer.from(fit));
});

test("unzip returns a stored entry", async () => {
  const entries = await unzip(makeZip("note.txt", new TextEncoder().encode("hello"), { deflate: false }));
  assert.equal(new TextDecoder().decode(entries[0].bytes), "hello");
});

test("unzip rejects data that is not a zip", async () => {
  await assert.rejects(() => unzip(new Uint8Array(64)), /Not a zip/);
});
