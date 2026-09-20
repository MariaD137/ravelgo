import { z } from "zod";

export const paginationQuerySchema = z.object({
  page: z.coerce.number().int().min(1).default(1),
  pageSize: z.coerce.number().int().min(1).max(100).default(20),
});

export type PaginationQuery = z.infer<typeof paginationQuerySchema>;

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
