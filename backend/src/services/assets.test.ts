import assert from "node:assert/strict";
import { test } from "node:test";
import { env } from "../config/env";
import { resolveAssetUrl } from "./assets";

test("resolveAssetUrl returns the bare key when ASSETS_PUBLIC_BASE_URL isn't configured", () => {
  const original = env.ASSETS_PUBLIC_BASE_URL;
  env.ASSETS_PUBLIC_BASE_URL = undefined;
  try {
    assert.equal(resolveAssetUrl("driver-sub-1/abc-photo.jpg"), "driver-sub-1/abc-photo.jpg");
  } finally {
    env.ASSETS_PUBLIC_BASE_URL = original;
  }
});

test("resolveAssetUrl joins the configured CDN base with the key", () => {
  const original = env.ASSETS_PUBLIC_BASE_URL;
  env.ASSETS_PUBLIC_BASE_URL = "https://d123.cloudfront.net";
  try {
    assert.equal(
      resolveAssetUrl("driver-sub-1/abc-photo.jpg"),
      "https://d123.cloudfront.net/driver-sub-1/abc-photo.jpg",
    );
  } finally {
    env.ASSETS_PUBLIC_BASE_URL = original;
  }
});

test("resolveAssetUrl strips a trailing slash from the configured base before joining", () => {
  const original = env.ASSETS_PUBLIC_BASE_URL;
  env.ASSETS_PUBLIC_BASE_URL = "https://d123.cloudfront.net/";
  try {
    assert.equal(
      resolveAssetUrl("driver-sub-1/abc-photo.jpg"),
      "https://d123.cloudfront.net/driver-sub-1/abc-photo.jpg",
    );
  } finally {
    env.ASSETS_PUBLIC_BASE_URL = original;
  }
});
