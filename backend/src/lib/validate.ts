/**
 * Validation helper for routes.
 * Usage: const data = validate(schema, req.body, "Request body");
 */

import { ZodSchema } from "zod";
import { formatZodError } from "./errors";

export function validate<T>(schema: ZodSchema, data: unknown, context: string = "Input"): T {
  const result = schema.safeParse(data);
  if (!result.success) {
    const error = formatZodError(result.error);
    // Add context to message
    error.message = `${context}: ${error.message}`;
    throw error;
  }
  return result.data;
}
