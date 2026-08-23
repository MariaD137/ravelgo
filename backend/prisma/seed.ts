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

  await seedDemoData();
}

// ============================================================================
// DEMO / SAMPLE DATA — for local development and UI/E2E testing only.
// ============================================================================
// Every record below is clearly marked as demo data: cognitoSub/email use a
// "demo-*" / "demo.*@ravelgo.test" convention, distinct from the seed-*
// fixtures above (which pre-date this section and remain untouched). None of
// this represents real users, businesses, or activity.
//
// Idempotent by construction: every entity has a natural unique key it's
// looked up by before creating (cognitoSub/email for User via upsert,
// plateNumber for Vehicle via upsert). Models below that have no natural
// unique key in the schema (Trip, CourierRequest, RentalListing,
// RentalBooking, DriverDocument, DriverAssignment) go through a small
// findOrCreate() helper that looks up an existing row by the same fields
// that make it unique *within this seed's fixed dataset* (e.g. a specific
// trip is fully identified by rider+driver+status+route) before creating —
// running `npm run prisma:seed` twice reuses those rows rather than
// duplicating them.
//
// There is no Business model in this schema (see schema.prisma — CourierRequest
// only relates to a User sender). The three demo "businesses" below are
// therefore represented as ordinary RIDER-role User accounts acting as
// courier senders, named so they read as businesses in any screen that
// displays a courier request's sender (e.g. "Demo Luxury Boutique
// (Business)") — the same representation the app already uses for every
// other courier sender, not a new concept.
async function seedDemoData() {
  console.log("Seeding demo data...");

  async function findOrCreate<T>(
    find: () => Promise<T | null>,
    create: () => Promise<T>,
  ): Promise<T> {
    const existing = await find();
    if (existing) return existing;
    return create();
  }

  // ---- Demo drivers (Objective 1: 3 approved ACTIVE demo drivers) ----
  const demoDriverSeeds = [
    { n: 1, first: "Demo", last: "Driver One", online: true, rating: 4.9, totalTrips: 128 },
    { n: 2, first: "Demo", last: "Driver Two", online: true, rating: 4.7, totalTrips: 302 },
    { n: 3, first: "Demo", last: "Driver Three", online: false, rating: 4.85, totalTrips: 76 },
  ] as const;

  const demoDrivers = [];
  for (const d of demoDriverSeeds) {
    const user = await prisma.user.upsert({
      where: { email: `demo.driver${d.n}@ravelgo.test` },
      update: {},
      create: {
        cognitoSub: `demo-driver-${d.n}`,
        role: "DRIVER",
        firstName: d.first,
        lastName: d.last,
        email: `demo.driver${d.n}@ravelgo.test`,
        phoneNumber: `+234700000000${d.n}`,
      },
    });
    const driverRow = await prisma.driver.upsert({
      where: { userId: user.id },
      update: { status: "ACTIVE", online: d.online, rating: d.rating, totalTrips: d.totalTrips },
      create: {
        userId: user.id,
        status: "ACTIVE",
        online: d.online,
        rating: d.rating,
        totalTrips: d.totalTrips,
        preferredLanguage: "English",
        subscriptionActive: true,
      },
    });
    demoDrivers.push({ user, driver: driverRow });

    // DriverDocument has no unique constraint (title is free text, not a
    // fixed enum), so createMany's skipDuplicates can't dedupe it — findOrCreate
    // by {driverId, title} instead, the same idempotency pattern used
    // throughout the rest of this section.
    for (const title of ["Driver's License", "Vehicle Registration (Car Papers)", "Insurance Certificate"]) {
      await findOrCreate(
        () => prisma.driverDocument.findFirst({ where: { driverId: driverRow.id, title } }),
        () => prisma.driverDocument.create({ data: { driverId: driverRow.id, title, status: "APPROVED" } }),
      );
    }
  }
  const [demoDriver1, demoDriver2, demoDriver3] = demoDrivers;

  // ---- Demo vehicles (Objective 2: exactly 3 clearly identified demo vehicles) ----
  const vehicle1 = await prisma.vehicle.upsert({
    where: { plateNumber: "DEMO-101-LG" },
    update: {},
    create: {
      driverId: demoDriver1.driver.id,
      brand: "Mercedes-Benz",
      model: "E-Class",
      colour: "Black",
      plateNumber: "DEMO-101-LG",
      year: "2023",
      isPrimary: true,
      listedForRental: true, // Demo vehicle — available for taxi and rental
    },
  });
  const vehicle2 = await prisma.vehicle.upsert({
    where: { plateNumber: "DEMO-202-LG" },
    update: {},
    create: {
      driverId: demoDriver2.driver.id,
      brand: "Toyota",
      model: "Land Cruiser",
      colour: "White",
      plateNumber: "DEMO-202-LG",
      year: "2022",
      isPrimary: true,
      listedForRental: true, // Demo vehicle — available for taxi and rental
    },
  });
  const vehicle3 = await prisma.vehicle.upsert({
    where: { plateNumber: "DEMO-303-LG" },
    update: {},
    create: {
      driverId: demoDriver3.driver.id,
      brand: "BMW",
      model: "7 Series",
      colour: "Grey",
      plateNumber: "DEMO-303-LG",
      year: "2024",
      isPrimary: true,
      listedForRental: true, // Demo vehicle — rental only (driver 3 stays offline for taxi)
    },
  });

  // ---- Demo riders (Objective 6) ----
  const demoRiderSeeds = [
    { n: 1, last: "Rider One" },
    { n: 2, last: "Rider Two" },
    { n: 3, last: "Rider Three" },
  ] as const;
  const demoRiders = [];
  for (const r of demoRiderSeeds) {
    const user = await prisma.user.upsert({
      where: { email: `demo.rider${r.n}@ravelgo.test` },
      update: {},
      create: {
        cognitoSub: `demo-rider-${r.n}`,
        role: "RIDER",
        firstName: "Demo",
        lastName: r.last,
        email: `demo.rider${r.n}@ravelgo.test`,
        phoneNumber: `+234700000010${r.n}`,
      },
    });
    demoRiders.push(user);
  }
  const [demoRider1, demoRider2, demoRider3] = demoRiders;

  // ---- Demo businesses (Objective 4) — no Business model exists (see
  // header comment above); represented as RIDER-role Users, the same shape
  // every other courier sender already uses. ----
  const demoBusinessSeeds = [
    { n: 1, first: "Demo Luxury", last: "Boutique (Business)" },
    { n: 2, first: "Demo Auto", last: "Parts (Business)" },
    { n: 3, first: "Demo", last: "Electronics (Business)" },
  ] as const;
  const demoBusinesses = [];
  for (const b of demoBusinessSeeds) {
    const user = await prisma.user.upsert({
      where: { email: `demo.business${b.n}@ravelgo.test` },
      update: {},
      create: {
        cognitoSub: `demo-business-${b.n}`,
        role: "RIDER",
        firstName: b.first,
        lastName: b.last,
        email: `demo.business${b.n}@ravelgo.test`,
        phoneNumber: `+234700000020${b.n}`,
      },
    });
    demoBusinesses.push(user);
  }
  const [demoBusiness1, demoBusiness2, demoBusiness3] = demoBusinesses;

  // ---- Taxi / ride-hailing demo data (Objective 3) ----
  const now = Date.now();
  const day = 24 * 60 * 60 * 1000;

  // 1 completed ride (history record #1).
  await findOrCreate(
    () =>
      prisma.trip.findFirst({
        where: { riderId: demoRider1.id, driverId: demoDriver1.driver.id, status: "COMPLETED", pickup: "Ikeja, Lagos" },
      }),
    () =>
      prisma.trip.create({
        data: {
          riderId: demoRider1.id,
          driverId: demoDriver1.driver.id,
          vehicleId: vehicle1.id,
          pickup: "Ikeja, Lagos",
          destination: "Victoria Island, Lagos",
          estimatedFare: 18.5,
          finalFare: 19.0,
          status: "COMPLETED",
          category: "Personal",
          requestedAt: new Date(now - 2 * day - 40 * 60 * 1000),
          completedAt: new Date(now - 2 * day),
        },
      }),
  );

  // 1 more completed ride (history record #2 — a second driver history entry).
  await findOrCreate(
    () =>
      prisma.trip.findFirst({
        where: { riderId: demoRider3.id, driverId: demoDriver1.driver.id, status: "COMPLETED", pickup: "Yaba, Lagos" },
      }),
    () =>
      prisma.trip.create({
        data: {
          riderId: demoRider3.id,
          driverId: demoDriver1.driver.id,
          vehicleId: vehicle1.id,
          pickup: "Yaba, Lagos",
          destination: "Surulere, Lagos",
          estimatedFare: 9.75,
          finalFare: 10.0,
          status: "COMPLETED",
          category: "Personal",
          requestedAt: new Date(now - 5 * day - 25 * 60 * 1000),
          completedAt: new Date(now - 5 * day),
        },
      }),
  );

  // 1 active/recent ride (IN_PROGRESS) — also makes demo driver 2 correctly
  // busy via a real DriverAssignment, exactly like a real matched ride.
  const activeTrip = await findOrCreate(
    () => prisma.trip.findFirst({ where: { riderId: demoRider2.id, driverId: demoDriver2.driver.id, status: "IN_PROGRESS" } }),
    () =>
      prisma.trip.create({
        data: {
          riderId: demoRider2.id,
          driverId: demoDriver2.driver.id,
          vehicleId: vehicle2.id,
          pickup: "Lekki Phase 1, Lagos",
          destination: "Ajah, Lagos",
          estimatedFare: 14.25,
          status: "IN_PROGRESS",
          category: "Personal",
          requestedAt: new Date(now - 15 * 60 * 1000),
        },
      }),
  );
  await findOrCreate(
    () =>
      prisma.driverAssignment.findFirst({
        where: { driverId: demoDriver2.driver.id, assignmentType: "RIDE", assignmentId: activeTrip.id },
      }),
    () =>
      prisma.driverAssignment.create({
        data: {
          driverId: demoDriver2.driver.id,
          assignmentType: "RIDE",
          assignmentId: activeTrip.id,
          vehicleId: vehicle2.id,
          status: "ACTIVE",
        },
      }),
  );

  // ---- Courier business + delivery demo data (Objective 4) ----

  // 1 completed delivery.
  await findOrCreate(
    () => prisma.courierRequest.findFirst({ where: { senderId: demoBusiness1.id, packageDescription: "Designer handbag order" } }),
    () =>
      prisma.courierRequest.create({
        data: {
          senderId: demoBusiness1.id,
          driverId: demoDriver1.driver.id,
          pickupAddress: "14 Adeola Odeku St, Victoria Island",
          dropoffAddress: "22 Awolowo Rd, Ikoyi",
          packageDescription: "Designer handbag order",
          recipientName: "Ngozi Bello",
          recipientPhone: "+234701555010",
          estimatedFare: 12.0,
          finalFare: 12.0,
          status: "DELIVERED",
          requestedAt: new Date(now - 3 * day - 60 * 60 * 1000),
          deliveredAt: new Date(now - 3 * day),
        },
      }),
  );

  // 1 delivery awaiting a driver (unassigned, REQUESTED).
  await findOrCreate(
    () => prisma.courierRequest.findFirst({ where: { senderId: demoBusiness2.id, packageDescription: "Brake pads and oil filter set" } }),
    () =>
      prisma.courierRequest.create({
        data: {
          senderId: demoBusiness2.id,
          pickupAddress: "8 Ogunlana Drive, Surulere",
          dropoffAddress: "45 Herbert Macaulay Way, Yaba",
          packageDescription: "Brake pads and oil filter set",
          recipientName: "Chuka Eze",
          recipientPhone: "+234701555020",
          estimatedFare: 8.5,
          status: "REQUESTED",
          requestedAt: new Date(now - 10 * 60 * 1000),
        },
      }),
  );

  // 1 delivery actively in transit — also makes demo driver 1 correctly busy
  // via a real DriverAssignment, exactly like a real accepted courier job.
  const activeCourier = await findOrCreate(
    () => prisma.courierRequest.findFirst({ where: { senderId: demoBusiness3.id, packageDescription: "Sealed laptop, insured" } }),
    () =>
      prisma.courierRequest.create({
        data: {
          senderId: demoBusiness3.id,
          driverId: demoDriver1.driver.id,
          pickupAddress: "5 Allen Avenue, Ikeja",
          dropoffAddress: "3 Admiralty Way, Lekki Phase 1",
          packageDescription: "Sealed laptop, insured",
          recipientName: "Fatima Aliyu",
          recipientPhone: "+234701555030",
          estimatedFare: 15.0,
          status: "IN_TRANSIT",
          requestedAt: new Date(now - 40 * 60 * 1000),
        },
      }),
  );
  await findOrCreate(
    () =>
      prisma.driverAssignment.findFirst({
        where: { driverId: demoDriver1.driver.id, assignmentType: "COURIER", assignmentId: activeCourier.id },
      }),
    () =>
      prisma.driverAssignment.create({
        data: {
          driverId: demoDriver1.driver.id,
          assignmentType: "COURIER",
          assignmentId: activeCourier.id,
          status: "ACTIVE",
        },
      }),
  );

  // ---- Vehicle rental demo data (Objective 5) ----
  const listing1 = await findOrCreate(
    () => prisma.rentalListing.findFirst({ where: { driverId: demoDriver1.driver.id, vehicleId: vehicle1.id } }),
    () =>
      prisma.rentalListing.create({
        data: { driverId: demoDriver1.driver.id, vehicleId: vehicle1.id, dailyRate: 120, location: "Lagos, Nigeria", status: "APPROVED" },
      }),
  );
  const listing2 = await findOrCreate(
    () => prisma.rentalListing.findFirst({ where: { driverId: demoDriver2.driver.id, vehicleId: vehicle2.id } }),
    () =>
      prisma.rentalListing.create({
        data: { driverId: demoDriver2.driver.id, vehicleId: vehicle2.id, dailyRate: 150, location: "Lagos, Nigeria", status: "APPROVED" },
      }),
  );
  const listing3 = await findOrCreate(
    () => prisma.rentalListing.findFirst({ where: { driverId: demoDriver3.driver.id, vehicleId: vehicle3.id } }),
    () =>
      prisma.rentalListing.create({
        data: { driverId: demoDriver3.driver.id, vehicleId: vehicle3.id, dailyRate: 200, location: "Lagos, Nigeria", status: "APPROVED" },
      }),
  );

  // 1 completed/past rental (no overlap with the other two — different vehicle each).
  await findOrCreate(
    () => prisma.rentalBooking.findFirst({ where: { rentalListingId: listing1.id, renterId: demoRider1.id, status: "COMPLETED" } }),
    () =>
      prisma.rentalBooking.create({
        data: {
          rentalListingId: listing1.id,
          renterId: demoRider1.id,
          vehicleId: vehicle1.id,
          startAt: new Date(now - 20 * day),
          endAt: new Date(now - 17 * day),
          status: "COMPLETED",
          price: 120 * 3,
        },
      }),
  );

  // 1 upcoming/confirmed rental.
  await findOrCreate(
    () => prisma.rentalBooking.findFirst({ where: { rentalListingId: listing2.id, renterId: demoRider2.id, status: "CONFIRMED" } }),
    () =>
      prisma.rentalBooking.create({
        data: {
          rentalListingId: listing2.id,
          renterId: demoRider2.id,
          vehicleId: vehicle2.id,
          startAt: new Date(now + 10 * day),
          endAt: new Date(now + 13 * day),
          status: "CONFIRMED",
          price: 150 * 3,
        },
      }),
  );

  // 1 currently active rental — also makes demo driver 3 correctly busy via
  // a real DriverAssignment, exactly like a real activated booking.
  const activeBooking = await findOrCreate(
    () => prisma.rentalBooking.findFirst({ where: { rentalListingId: listing3.id, renterId: demoRider3.id, status: "ACTIVE" } }),
    () =>
      prisma.rentalBooking.create({
        data: {
          rentalListingId: listing3.id,
          renterId: demoRider3.id,
          vehicleId: vehicle3.id,
          startAt: new Date(now - 1 * day),
          endAt: new Date(now + 2 * day),
          status: "ACTIVE",
          price: 200 * 3,
        },
      }),
  );
  await findOrCreate(
    () =>
      prisma.driverAssignment.findFirst({
        where: { driverId: demoDriver3.driver.id, assignmentType: "RENTAL", assignmentId: activeBooking.id },
      }),
    () =>
      prisma.driverAssignment.create({
        data: {
          driverId: demoDriver3.driver.id,
          assignmentType: "RENTAL",
          assignmentId: activeBooking.id,
          vehicleId: vehicle3.id,
          status: "ACTIVE",
        },
      }),
  );

  console.log("Demo data seed complete:", {
    demoDrivers: demoDriverSeeds.map((d) => `demo.driver${d.n}@ravelgo.test`),
    demoRiders: demoRiderSeeds.map((r) => `demo.rider${r.n}@ravelgo.test`),
    demoBusinesses: demoBusinessSeeds.map((b) => `demo.business${b.n}@ravelgo.test`),
    demoVehicles: [vehicle1.plateNumber, vehicle2.plateNumber, vehicle3.plateNumber],
  });
}

main()
  .catch((err) => {
    console.error(err);
    process.exitCode = 1;
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
