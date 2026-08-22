import { prisma } from "../db/prisma";

// Shared by every route that needs "the Driver row for the caller's own
// Cognito identity" — was duplicated verbatim across courier.routes.ts,
// rentals.routes.ts, vehicles.routes.ts, and inlined again in
// trips.routes.ts before this extraction.
export async function findOwnDriver(cognitoSub: string) {
  return prisma.driver.findFirst({ where: { user: { cognitoSub } } });
}
