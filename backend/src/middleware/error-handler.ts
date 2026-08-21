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

  // Body-parser (and similar middleware) throw HTTP-error-shaped objects
  // for client-input problems — e.g. malformed JSON — with .statusCode/
  // .status in the 4xx range and .expose=true (their own signal that the
  // error is safe to report, as opposed to an internal failure). Without
  // this, those fall through to the generic 500 below: a malformed request
  // body would incorrectly count as a server error against
  // MonitoringStack's 5xx alarm, and misreport a client mistake as ours.
  // The underlying err.message (which can echo raw request bytes, e.g.
  // body-parser's parse error) is never sent to the client — only a fixed,
  // generic message.
  const httpErr = err as { statusCode?: number; status?: number; expose?: boolean };
  const httpStatus = httpErr.statusCode ?? httpErr.status;
  if (typeof httpStatus === "number" && httpStatus >= 400 && httpStatus < 500 && httpErr.expose) {
    const response: ErrorResponse = {
      error: {
        code: ErrorCodes.BAD_REQUEST,
        message: "Malformed request",
        timestamp: new Date().toISOString(),
      },
    };
    return res.status(httpStatus).json(response);
  }

  // Handle Prisma errors
  if (err.name === "PrismaClientKnownRequestError") {
    const prismaErr = err as any;
    if (prismaErr.code === "P2002") {
      // Unique constraint violation
      const response: ErrorResponse = {
        error: {
          code: ErrorCodes.CONFLICT,
          message: `Duplicate value for field: ${prismaErr.meta?.target?.[0] || "unknown"}`,
          timestamp: new Date().toISOString(),
        },
      };
      return res.status(409).json(response);
    }

    if (prismaErr.code === "P2025") {
      // Record not found
      const response: ErrorResponse = {
        error: {
          code: ErrorCodes.NOT_FOUND,
          message: "Record not found",
          timestamp: new Date().toISOString(),
        },
      };
      return res.status(404).json(response);
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
