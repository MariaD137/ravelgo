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
