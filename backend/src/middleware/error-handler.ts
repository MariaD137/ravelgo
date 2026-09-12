import type { Prisma } from "@prisma/client";
import { type NextFunction, type Request, type Response } from "express";
import { ApiError, ErrorCodes, ErrorResponse } from "../lib/errors";

/**
 * Global error handler middleware.
 * Must be registered last in Express app.
 */
export function errorHandler(err: Error, _req: Request, res: Response, _next: NextFunction) {
  console.error(err);

  // Handle our custom ApiError
  if (err instanceof ApiError) {
    const response: ErrorResponse = {
      error: {
        code: err.code,
        message: err.message,
        details: err.details,
        timestamp: new Date().toISOString(),
      },
    };
    return res.status(err.statusCode).json(response);
  }

  // Handle Prisma errors
  if (err.name === "PrismaClientKnownRequestError") {
    const prismaErr = err as Prisma.PrismaClientKnownRequestError;
    if (prismaErr.code === "P2002") {
      // Unique constraint violation
      const target = prismaErr.meta?.target;
      const field = Array.isArray(target) ? target[0] : "unknown";
      const response: ErrorResponse = {
        error: {
          code: ErrorCodes.CONFLICT,
          message: `Duplicate value for field: ${field}`,
          timestamp: new Date().toISOString(),
        },
      };
      return res.status(409).json(response);
    }

    if (prismaErr.code === "P2025") {
      // Record not found (e.g. update/delete of a row that doesn't exist)
      const response: ErrorResponse = {
        error: {
          code: ErrorCodes.NOT_FOUND,
          message: "Record not found",
          timestamp: new Date().toISOString(),
        },
      };
      return res.status(404).json(response);
    }

    if (prismaErr.code === "P2003") {
      // Foreign-key constraint violation — a referenced record is missing, or
      // a still-referenced record was being removed. The client's request
      // referenced something invalid; never echo the raw constraint name.
      const response: ErrorResponse = {
        error: {
          code: ErrorCodes.CONFLICT,
          message: "Operation references a record that does not exist or is still in use",
          timestamp: new Date().toISOString(),
        },
      };
      return res.status(409).json(response);
    }

    if (prismaErr.code === "P2021" || prismaErr.code === "P2022") {
      // A table (P2021) or column (P2022) the code expects doesn't exist:
      // the deployed database is behind the deployed code because a Prisma
      // migration was never applied (scripts/migrate-staging.sh /
      // migrate-production.sh). This is an operator problem, not a client
      // one, and the single most likely cause of a whole feature 500-ing
      // after a deploy — so name it in the log AND the response, so a
      // rider-facing "Could not get fare estimates" can be traced to it
      // without App Runner log access. The raw table/column name stays in
      // the server log only.
      console.error(
        `[schema] ${prismaErr.code}: the database is missing a table/column the code expects — pending Prisma migrations have not been applied to this environment. Run scripts/migrate-<env>.sh.`,
      );
      const response: ErrorResponse = {
        error: {
          code: ErrorCodes.DATABASE_ERROR,
          message: "Database schema is out of date on this server (pending migrations not applied)",
          timestamp: new Date().toISOString(),
        },
      };
      return res.status(500).json(response);
    }

    // Other Prisma errors
    const response: ErrorResponse = {
      error: {
        code: ErrorCodes.DATABASE_ERROR,
        message: "Database operation failed",
        timestamp: new Date().toISOString(),
      },
    };
    return res.status(500).json(response);
  }

  // Paystack refused the request, was unreachable, or isn't configured on
  // this server (src/billing/paystack.ts throws with status 503 for the
  // latter before any network call). Surface it as a distinct, safe error
  // instead of a generic 500: the client can tell "payments are down" apart
  // from "the app crashed", and the full Paystack message is already in the
  // server log above. Duck-typed on name (like the Prisma branch) so this
  // middleware doesn't import the billing module.
  if (err.name === "PaystackApiError") {
    const providerStatus = (err as { status?: number }).status;
    const unconfigured = providerStatus === 503;
    const response: ErrorResponse = {
      error: {
        code: ErrorCodes.PAYMENT_PROVIDER_ERROR,
        message: unconfigured
          ? "Payments are not configured on this server yet"
          : "The payment provider could not process this request",
        timestamp: new Date().toISOString(),
      },
    };
    return res.status(unconfigured ? 503 : 502).json(response);
  }

  // Default 500 error
  const response: ErrorResponse = {
    error: {
      code: ErrorCodes.INTERNAL_SERVER_ERROR,
      message: "Internal server error",
      timestamp: new Date().toISOString(),
    },
  };
  res.status(500).json(response);
}
