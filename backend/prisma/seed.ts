import { PrismaClient } from "@prisma/client";

const prisma = new PrismaClient();

async function main() {
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

  await prisma.carPaddyRequest.create({
    data: { driverId: driver.id, plateNumber: vehicle.plateNumber, status: "IN_REVIEW" },
  });

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

  await prisma.supportTicket.create({
    data: {
      userId: rider.id,
      subject: "Lost phone in a recent trip",
      category: "Lost item",
      status: "OPEN",
    },
  });

  // Without an active PricingRule, POST /trips can't validate a client's
  // estimatedFare against anything and GET /pricing/quote 409s outright —
  // see FINAL_AWS_STAGING_DEPLOYMENT_READINESS.md. These numbers are a
  // deliberately plain, round PLACEHOLDER (base fare + per-km + per-minute
  // in USD) chosen only to make the pricing engine functional in a fresh
  // environment — they are NOT researched RavelGo business pricing and
  // MUST be replaced (PATCH /api/pricing-rules/:id, or a new active rule)
  // before any real fare is charged to a real user. Only seeds one if no
  // active rule exists yet at all, so re-running this script never creates
  // a second active rule or overwrites pricing an admin has since
  // configured for real.
  const existingActiveRule = await prisma.pricingRule.findFirst({ where: { active: true } });
  if (!existingActiveRule) {
    await prisma.pricingRule.upsert({
      where: { name: "Staging Default (PLACEHOLDER — replace before production)" },
      update: {},
      create: {
        name: "Staging Default (PLACEHOLDER — replace before production)",
        baseFare: 2.0,
        perKm: 1.0,
        perMinute: 0.25,
        active: true,
      },
    });
    console.log("Seeded a placeholder active PricingRule (baseFare=2.00, perKm=1.00, perMinute=0.25 USD) for staging.");
    console.log("This is NOT real business pricing — replace it before production, see FINAL_AWS_STAGING_DEPLOYMENT_READINESS.md.");
  } else {
    console.log(`An active PricingRule already exists ("${existingActiveRule.name}") — skipping placeholder seed.`);
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
