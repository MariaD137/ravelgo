import { rateLimit } from "express-rate-limit";
import type { Request, Response } from "express";
import { env } from "../config/env";
import { logSecurityEvent } from "../lib/security-log";

const FIFTEEN_MIN = 15 * 60 * 1000;

/**
 * A rate limiter with a consistent 429 body and a logged security event.
 *
 * Two deliberate choices, both learned from the earlier RavelGo incident
 * where an over-aggressive global limiter 429'd normal users:
 *  - Limits are sized so a normal user session never reaches them (a rider
 *    requesting a few trips, a driver charging a few fares, onboarding
 *    uploads) — they exist to stop scripted abuse, not real usage.
 *  - Every limiter is keyed per-IP and skipped entirely under test, matching
 *    the existing global limiter in app.ts, so the suite stays deterministic.
 *    The limiter behaviour itself is covered directly in
 *    middleware/rate-limit.test.ts against a throwaway app with a low limit.
 */
export function createRateLimiter(options: {
  limit: number;
  windowMs?: number;
  name: string;
  // Defaults to skipping under test so the suite stays deterministic; the
  // limiter's own enforcement is covered directly in rate-limit.test.ts by
  // passing `skip: () => false`.
  skip?: () => boolean;
}) {
  return rateLimit({
    windowMs: options.windowMs ?? FIFTEEN_MIN,
    limit: options.limit,
    standardHeaders: true,
    legacyHeaders: false,
    skip: options.skip ?? (() => env.NODE_ENV === "test"),
    handler: (req: Request, res: Response) => {
      logSecurityEvent("RATE_LIMIT_EXCEEDED", req, { limiter: options.name });
      res.status(429).json({
        error: {
          code: "RATE_LIMIT_EXCEEDED",
          message: "Too many requests. Please slow down and try again shortly.",
          timestamp: new Date().toISOString(),
        },
      });
    },
  });
}

// Expensive or abuse-prone operations that cost real money or storage:
// presigning uploads (S3), charging a card (Stripe), creating/processing
// payouts, and creating trips (each triggers matching + a DB write). Sized
// far above any legitimate single-session burst.
export const sensitiveLimiter = createRateLimiter({ limit: 40, name: "sensitive" });

// Address search fires on nearly every keystroke and each call costs a real
// Google Places request, so this sits above a normal typing burst but well
// under what scripted abuse of the paid API would need.
export const placesLimiter = createRateLimiter({ limit: 200, name: "places" });

// The Stripe webhook is authenticated by signature, and Stripe legitimately
// retries, so this ceiling is high — it's a flood backstop, not a throttle on
// normal delivery, and a dropped webhook here would be re-sent by Stripe.
export const webhookLimiter = createRateLimiter({ limit: 600, windowMs: 60 * 1000, name: "webhook" });
