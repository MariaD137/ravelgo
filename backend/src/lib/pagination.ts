import { z } from "zod";

export const paginationQuerySchema = z.object({
  page: z.coerce.number().int().min(1).default(1),
  pageSize: z.coerce.number().int().min(1).max(100).default(20),
});

export type PaginationQuery = z.infer<typeof paginationQuerySchema>;

// Shared free-text search param (?q=...) every admin list endpoint that
// supports search extends onto paginationQuerySchema, the same way each
// already extends it with its own status filter. Trimmed and length-capped
// so a stray very long value can't build an absurd query; empty/whitespace
// collapses to undefined (no filter) rather than matching everything.
export const searchQuerySchema = z.object({
  q: z
    .string()
    .trim()
    .max(200)
    .optional()
    .transform((v) => (v && v.length > 0 ? v : undefined)),
});

export interface Paginated<T> {
  data: T[];
  page: number;
  pageSize: number;
  total: number;
  // Additive navigation metadata (the Admin App pages through every list
  // with these; the original four fields are unchanged for every existing
  // caller). totalPages is 1 when total is 0 so "page 1 of 1" still reads
  // sensibly on an empty list; hasNext is derived from the same numbers.
  totalPages: number;
  hasNext: boolean;
}

export function paginate<T>(data: T[], total: number, page: number, pageSize: number): Paginated<T> {
  const totalPages = Math.max(1, Math.ceil(total / pageSize));
  return { data, page, pageSize, total, totalPages, hasNext: page < totalPages };
}

/**
 * Parses an optional comma-separated enum filter (`?status=A,B`) into a
 * Prisma `in` clause, or undefined when the query param is absent. Used by
 * the admin list endpoints so multi-select status chips in the Admin App
 * filter server-side (across the whole table) rather than within one page.
 * Unknown values are rejected by the zod schema that feeds this, so by the
 * time it runs every entry is a valid enum member.
 */
export function inFilter<T extends string>(values: readonly T[] | undefined): { in: T[] } | undefined {
  return values && values.length > 0 ? { in: [...values] } : undefined;
}

/** zod preprocessor: "A,B" -> ["A","B"]; leaves arrays/undefined alone. */
export function csvList(value: unknown): unknown {
  if (typeof value === "string") {
    return value
      .split(",")
      .map((v) => v.trim())
      .filter((v) => v.length > 0);
  }
  return value;
}

/**
 * Builds a case-insensitive Prisma `contains` filter for a single field, or
 * undefined when there's no search term — spread that into a where clause's
 * OR array. Kept to one field at a time (rather than returning the whole OR
 * array) since each route's set of searchable fields — and how deeply
 * nested they are behind a relation — differs enough that composing the OR
 * array itself reads more clearly written out at each call site.
 */
export function containsInsensitive(q: string | undefined) {
  return q ? { contains: q, mode: "insensitive" as const } : undefined;
}
