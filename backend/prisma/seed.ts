import { PrismaClient } from "@prisma/client";

const prisma = new PrismaClient();

/**
 * Refuse to run against anything that looks like production (P0 #14). This seed
 * creates an ACTIVE, online, matchable driver and a wallet with a real
 * spendable balance — harmless demo data in dev/test, dangerous in prod
 * (a real rider could be matched to a ghost driver, and un-funded money could
 * be spent on rides). Guard requires BOTH:
 *   - NODE_ENV must not be "production", and
 *   - ALLOW_DEMO_SEED=true must be set explicitly.
 * so no single misconfigured env var can seed a production database.
 */
function assertSeedingAllowed(): void {
  const nodeEnv = process.env.NODE_ENV;
  if (nodeEnv === "production") {
    throw new Error("Refusing to seed: NODE_ENV=production. Demo seed data must never touch production.");
  }
  if (process.env.ALLOW_DEMO_SEED !== "true") {
    throw new Error(
      "Refusing to seed: set ALLOW_DEMO_SEED=true to confirm this is a development/test database. " +
        "This seed creates a matchable demo driver and a funded wallet and must never run against real data.",
    );
  }
  const url = process.env.DATABASE_URL ?? "";
  if (/\b(prod|production)\b/i.test(url)) {
    throw new Error(`Refusing to seed: DATABASE_URL looks production-like (${url.replace(/:\/\/.*@/, "://***@")}).`);
  }
}

async function main() {
  assertSeedingAllowed();
  console.log("Seeding...");

  const rider = await prisma.user.upsert({
    where: { email: "amaka.obi@example.com" },
    update: {},
    create: {
      cognitoSub: "seed-rider-amaka",
      role: "RIDER",
      firstName: "Amaka",
      lastName: "Obi",
      email: "amaka.obi@example.com",
      phoneNumber: "+2348012345001",
      isLoyaltyMember: true,
    },
  });

  const driverUser = await prisma.user.upsert({
    where: { email: "thelma.ibeh@example.com" },
    update: {},
    create: {
      cognitoSub: "seed-driver-thelma",
      role: "DRIVER",
      firstName: "Thelma",
      lastName: "Ibeh",
      email: "thelma.ibeh@example.com",
      phoneNumber: "+2347037530052",
    },
  });

  const driver = await prisma.driver.upsert({
    where: { userId: driverUser.id },
    update: {},
    create: {
      userId: driverUser.id,
      status: "ACTIVE",
      isOnline: true,
      rating: 4.8,
      totalTrips: 214,
      preferredLanguage: "English",
      subscriptionActive: true,
    },
  });

  const vehicle = await prisma.vehicle.upsert({
    where: { plateNumber: "LND-482-KJ" },
    update: {},
    create: {
      driverId: driver.id,
      brand: "Toyota",
      model: "Camry",
      colour: "Black",
      plateNumber: "LND-482-KJ",
      year: "2021",
      isPrimary: true,
    },
  });

  await prisma.driverDocument.createMany({
    data: [
      { driverId: driver.id, title: "Driver's License", status: "APPROVED" },
      { driverId: driver.id, title: "Vehicle Registration (Car Papers)", status: "EXPIRING_SOON" },
      { driverId: driver.id, title: "Insurance Certificate", status: "PENDING" },
    ],
    skipDuplicates: true,
  });

  // Guarded so re-running the seed (e.g. against staging) doesn't pile up
  // duplicate demo rows. The pricing rule and wallet below use upsert already.
  if ((await prisma.carPaddyRequest.count({ where: { driverId: driver.id } })) === 0) {
    await prisma.carPaddyRequest.create({
      data: { driverId: driver.id, plateNumber: vehicle.plateNumber, status: "IN_REVIEW" },
    });
  }

  // An active pricing rule is required for POST /trips to compute a fare
  // (the backend never trusts a client-supplied fare — see
  // src/services/pricing.ts), so ship one so the app works out of the box.
  await prisma.pricingRule.upsert({
    where: { name: "Standard" },
    update: {},
    create: { name: "Standard", baseFare: 500, perKm: 120, perMinute: 25, active: true },
  });

  // A funded demo wallet so the rider can pay by RavelGo wallet out of the box.
  await prisma.walletAccount.upsert({
    where: { userId: rider.id },
    update: {},
    create: { userId: rider.id, balanceCents: 500000 }, // ₦5,000.00 equivalent in the app's cent unit
  });

  if ((await prisma.trip.count({ where: { riderId: rider.id } })) === 0) {
    await prisma.trip.create({
      data: {
        riderId: rider.id,
        driverId: driver.id,
        pickup: "Lekki Phase 1",
        destination: "Victoria Island",
        estimatedFare: 3200,
        finalFare: 3200,
        status: "COMPLETED",
        category: "Business",
        completedAt: new Date(),
      },
    });
  }

  if ((await prisma.supportTicket.count({ where: { userId: rider.id } })) === 0) {
    await prisma.supportTicket.create({
      data: {
        userId: rider.id,
        subject: "Lost phone in a recent trip",
        category: "Lost item",
        status: "OPEN",
      },
    });
  }

  // Eats marketplace demo data.
  if ((await prisma.restaurant.count()) === 0) {
    const mamaPut = await prisma.restaurant.create({
      data: {
        name: "Mama Put Kitchen",
        cuisine: "Nigerian",
        address: "12 Adewale Crescent, Oshodi, Lagos",
        isOpen: true,
        rating: 4.6,
        menuItems: {
          create: [
            { name: "Jollof Rice & Chicken", description: "Smoky party jollof with grilled chicken", price: 3500 },
            { name: "Pounded Yam & Egusi", description: "With assorted meat", price: 4200 },
            { name: "Suya Platter", description: "Spicy grilled beef skewers", price: 2800 },
            { name: "Chapman", description: "Chilled Nigerian cocktail (non-alcoholic)", price: 1200 },
          ],
        },
      },
    });
    await prisma.restaurant.create({
      data: {
        name: "Lagos Grill House",
        cuisine: "Continental",
        address: "5 Marina Road, Victoria Island, Lagos",
        isOpen: true,
        rating: 4.4,
        menuItems: {
          create: [
            { name: "Beef Shawarma", description: "Double beef, garlic sauce", price: 3000 },
            { name: "Grilled Tilapia", description: "Whole fish with plantain", price: 5500 },
            { name: "Chicken & Chips", description: "Crispy fried chicken with fries", price: 4000 },
          ],
        },
      },
    });
    console.log("Seeded restaurants:", mamaPut.name, "and Lagos Grill House");
  }

  console.log("Seed complete:", { rider: rider.email, driver: driverUser.email, vehicle: vehicle.plateNumber });
}

main()
  .catch((err) => {
    console.error(err);
    process.exitCode = 1;
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
