/**
 * Field-level encryption for sensitive data at rest (bank account/routing
 * numbers) — AES-256-GCM. Ciphertext is stored as `${ivBase64}:${authTagBase64}:${dataBase64}`
 * so it fits in an existing String column with no schema change.
 */

import { createCipheriv, createDecipheriv, randomBytes } from "crypto";
import { env } from "../config/env";

const ALGORITHM = "aes-256-gcm";
const IV_LENGTH = 12; // recommended for GCM

// Fixed, clearly-labeled dev-only key so local dev/test never needs to set
// FIELD_ENCRYPTION_KEY — never used in production (env.ts throws at boot if
// FIELD_ENCRYPTION_KEY is unset there).
const DEV_ONLY_KEY = Buffer.from("ravelgo-dev-only-key-do-not-use-in-prod!!", "utf-8").subarray(0, 32);

function getKey(): Buffer {
  if (!env.FIELD_ENCRYPTION_KEY) return DEV_ONLY_KEY;
  const key = Buffer.from(env.FIELD_ENCRYPTION_KEY, "base64");
  if (key.length !== 32) {
    throw new Error("FIELD_ENCRYPTION_KEY must decode to exactly 32 bytes (AES-256)");
  }
  return key;
}

export function encryptField(plaintext: string): string {
  const iv = randomBytes(IV_LENGTH);
  const cipher = createCipheriv(ALGORITHM, getKey(), iv);
  const encrypted = Buffer.concat([cipher.update(plaintext, "utf-8"), cipher.final()]);
  const authTag = cipher.getAuthTag();
  return `${iv.toString("base64")}:${authTag.toString("base64")}:${encrypted.toString("base64")}`;
}

export function decryptField(ciphertext: string): string {
  const [ivB64, authTagB64, dataB64] = ciphertext.split(":");
  if (!ivB64 || !authTagB64 || !dataB64) {
    throw new Error("Malformed encrypted field value");
  }
  const decipher = createDecipheriv(ALGORITHM, getKey(), Buffer.from(ivB64, "base64"));
  decipher.setAuthTag(Buffer.from(authTagB64, "base64"));
  const decrypted = Buffer.concat([decipher.update(Buffer.from(dataB64, "base64")), decipher.final()]);
  return decrypted.toString("utf-8");
}

/** Last 4 characters only, for display — never return a decrypted full value over the API. */
export function maskLast4(plaintext: string): string {
  return `****${plaintext.slice(-4)}`;
}
