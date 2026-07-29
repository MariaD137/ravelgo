/**
 * Standardized error responses for the RavelGo API.
 * All endpoints should use these formats for consistent error handling.
 */

export interface ValidationError {
  field: string;
  message: string;
  code?: string;
}

export interface ErrorResponse {
  error: {
    code: string;
    message: string;
    details?: ValidationError[];
    timestamp: string;
  };
}

export class ApiError extends Error {
  constructor(
    public statusCode: number,
    public code: string,
    message: string,
    public details?: ValidationError[],
  ) {
    super(message);
    this.name = "ApiError";
  }
}

// Predefined error codes
export const ErrorCodes = {
  VALIDATION_ERROR: "VALIDATION_ERROR",
  AUTHENTICATION_ERROR: "AUTHENTICATION_ERROR",
  AUTHORIZATION_ERROR: "AUTHORIZATION_ERROR",
  NOT_FOUND: "NOT_FOUND",
  CONFLICT: "CONFLICT",
  INTERNAL_SERVER_ERROR: "INTERNAL_SERVER_ERROR",
  RATE_LIMIT_EXCEEDED: "RATE_LIMIT_EXCEEDED",
  BAD_REQUEST: "BAD_REQUEST",
  PAYMENT_ERROR: "PAYMENT_ERROR",
  DATABASE_ERROR: "DATABASE_ERROR",
} as const;

// Error response builders
export const Errors = {
  validation: (message: string, details?: ValidationError[]): ApiError =>
    new ApiError(400, ErrorCodes.VALIDATION_ERROR, message, details),

  authentication: (message: string = "Authentication required"): ApiError =>
    new ApiError(401, ErrorCodes.AUTHENTICATION_ERROR, message),

  authorization: (message: string = "Insufficient permissions"): ApiError =>
    new ApiError(403, ErrorCodes.AUTHORIZATION_ERROR, message),

  notFound: (resource: string): ApiError =>
    new ApiError(404, ErrorCodes.NOT_FOUND, `${resource} not found`),

  conflict: (message: string): ApiError =>
    new ApiError(409, ErrorCodes.CONFLICT, message),

  badRequest: (message: string): ApiError =>
    new ApiError(400, ErrorCodes.BAD_REQUEST, message),

  paymentError: (message: string): ApiError =>
    new ApiError(402, ErrorCodes.PAYMENT_ERROR, message),

  rateLimitExceeded: (): ApiError =>
    new ApiError(429, ErrorCodes.RATE_LIMIT_EXCEEDED, "Too many requests"),

  internalServerError: (message: string = "Internal server error"): ApiError =>
    new ApiError(500, ErrorCodes.INTERNAL_SERVER_ERROR, message),
};

/**
 * Convert Zod validation errors to our standardized format.
 * Example:
 *   const parsed = schema.safeParse(data);
 *   if (!parsed.success) {
 *     throw formatZodError(parsed.error);
 *   }
 */
export function formatZodError(zodError: any): ApiError {
  const details: ValidationError[] = [];

  if (zodError.issues) {
    for (const issue of zodError.issues) {
      details.push({
        field: issue.path.join(".") || "root",
        message: issue.message,
        code: issue.code,
      });
    }
  }

  return Errors.validation("Validation failed", details);
}
