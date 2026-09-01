import assert from "node:assert/strict";
import { after, afterEach, beforeEach, test } from "node:test";
import request from "supertest";
import { app } from "../app";
import { prisma } from "../db/prisma";
import { mockAuthAs, restoreAuth, resetDb } from "../test/helpers";

beforeEach(resetDb);
afterEach(() => {
  restoreAuth();
});
after(async () => {
  await resetDb();
  await prisma.$disconnect();
});

async function seedRider() {
  return prisma.user.create({
    data: {
      cognitoSub: "eats-rider-1",
      role: "RIDER",
      firstName: "Ada",
      lastName: "Rider",
      email: "ada.eats@example.com",
    },
  });
}

async function seedRestaurant() {
  return prisma.restaurant.create({
    data: {
      name: "Mama Put Kitchen",
      cuisine: "Nigerian",
      address: "12 Adewale Crescent, Lagos",
      isOpen: true,
      menuItems: {
        create: [
          { name: "Jollof Rice & Chicken", price: 3500 },
          { name: "Suya Platter", price: 2800 },
        ],
      },
    },
    include: { menuItems: true },
  });
}

test("GET /eats/restaurants lists open restaurants for an authed rider", async () => {
  await seedRestaurant();
  const token = mockAuthAs({ sub: "eats-rider-1", groups: ["Rider"] });

  const res = await request(app)
    .get("/api/eats/restaurants")
    .set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 200);
  assert.equal(res.body.items.length, 1);
  assert.equal(res.body.items[0].name, "Mama Put Kitchen");
});

test("GET /eats/restaurants/:id returns the restaurant with its menu", async () => {
  const restaurant = await seedRestaurant();
  const token = mockAuthAs({ sub: "eats-rider-1", groups: ["Rider"] });

  const res = await request(app)
    .get(`/api/eats/restaurants/${restaurant.id}`)
    .set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 200);
  assert.equal(res.body.menuItems.length, 2);
});

test("POST /eats/orders computes the total server-side from live prices", async () => {
  await seedRider();
  const restaurant = await seedRestaurant();
  const jollof = restaurant.menuItems.find((m) => m.name.startsWith("Jollof"))!;
  const token = mockAuthAs({ sub: "eats-rider-1", groups: ["Rider"] });

  const res = await request(app)
    .post("/api/eats/orders")
    .set("Authorization", `Bearer ${token}`)
    .send({
      restaurantId: restaurant.id,
      deliveryAddress: "5 Marina Road, Lagos",
      // A client-supplied price here is ignored; the server uses the menu price.
      items: [{ menuItemId: jollof.id, quantity: 2, price: 1 }],
    });

  assert.equal(res.status, 201);
  assert.equal(res.body.subtotal, 7000); // 3500 * 2
  assert.equal(res.body.deliveryFee, 500);
  assert.equal(res.body.total, 7500);
  assert.equal(res.body.items.length, 1);
  assert.equal(res.body.items[0].unitPrice, 3500);
});

test("POST /eats/orders rejects a Driver caller", async () => {
  const restaurant = await seedRestaurant();
  const token = mockAuthAs({ sub: "eats-driver-1", groups: ["Driver"] });

  const res = await request(app)
    .post("/api/eats/orders")
    .set("Authorization", `Bearer ${token}`)
    .send({
      restaurantId: restaurant.id,
      deliveryAddress: "5 Marina Road, Lagos",
      items: [{ menuItemId: restaurant.menuItems[0].id, quantity: 1 }],
    });

  assert.equal(res.status, 403);
});

test("GET /eats/orders/mine returns only the caller's orders", async () => {
  await seedRider();
  const restaurant = await seedRestaurant();
  const token = mockAuthAs({ sub: "eats-rider-1", groups: ["Rider"] });

  await request(app)
    .post("/api/eats/orders")
    .set("Authorization", `Bearer ${token}`)
    .send({
      restaurantId: restaurant.id,
      deliveryAddress: "5 Marina Road, Lagos",
      items: [{ menuItemId: restaurant.menuItems[0].id, quantity: 1 }],
    });

  const res = await request(app)
    .get("/api/eats/orders/mine")
    .set("Authorization", `Bearer ${token}`);

  assert.equal(res.status, 200);
  assert.equal(res.body.length, 1);
  assert.equal(res.body[0].items.length, 1);
});
