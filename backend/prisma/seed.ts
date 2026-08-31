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
