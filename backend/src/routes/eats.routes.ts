import { Router } from "express";
import { z } from "zod";
import { prisma } from "../db/prisma";
import { requireAuth, requireRole } from "../middleware/auth";
import { paginate, paginationQuerySchema } from "../lib/pagination";

export const eatsRouter = Router();

// Flat delivery fee (server-authoritative — never trusted from the client).
const DELIVERY_FEE = 500;

// Browse restaurants. Non-admins only see open ones; admins see all.
eatsRouter.get("/eats/restaurants", requireAuth, async (req, res) => {
  const parsed = paginationQuerySchema.safeParse(req.query);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const { page, pageSize } = parsed.data;

  const where = req.user!.groups.includes("Admin") ? {} : { isOpen: true };
  const [items, total] = await Promise.all([
    prisma.restaurant.findMany({
      where,
      orderBy: { createdAt: "desc" },
      skip: (page - 1) * pageSize,
      take: pageSize,
    }),
    prisma.restaurant.count({ where }),
  ]);
  res.json(paginate(items, total, page, pageSize));
});

// Restaurant detail with its available menu.
eatsRouter.get("/eats/restaurants/:id", requireAuth, async (req, res) => {
  const restaurant = await prisma.restaurant.findUnique({
    where: { id: req.params.id },
    include: { menuItems: { where: { available: true }, orderBy: { name: "asc" } } },
  });
  if (!restaurant) return res.status(404).json({ error: "Restaurant not found" });
  res.json(restaurant);
});

const placeOrderSchema = z.object({
  restaurantId: z.string().min(1),
  deliveryAddress: z.string().min(3),
  items: z
    .array(
      z.object({
        menuItemId: z.string().min(1),
        quantity: z.number().int().positive().max(50),
      }),
    )
    .min(1),
});

// Rider: place a food order. Totals are computed on the server from the live
// menu prices — the client never asserts a price.
eatsRouter.post("/eats/orders", requireAuth, requireRole("Rider"), async (req, res) => {
  const parsed = placeOrderSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const { restaurantId, deliveryAddress, items } = parsed.data;

  const user = await prisma.user.findUnique({ where: { cognitoSub: req.user!.sub } });
  if (!user) return res.status(404).json({ error: "User not found" });

  const restaurant = await prisma.restaurant.findUnique({ where: { id: restaurantId } });
  if (!restaurant || !restaurant.isOpen) {
    return res.status(409).json({ error: "Restaurant is not accepting orders" });
  }

  const menuIds = items.map((i) => i.menuItemId);
  const menuItems = await prisma.menuItem.findMany({
    where: { id: { in: menuIds }, restaurantId, available: true },
  });
  if (menuItems.length !== new Set(menuIds).size) {
    return res.status(400).json({ error: "One or more items are unavailable" });
  }
  const byId = new Map(menuItems.map((m) => [m.id, m]));

  let subtotal = 0;
  const orderItems = items.map((i) => {
    const m = byId.get(i.menuItemId)!;
    subtotal += m.price * i.quantity;
    return { menuItemId: m.id, nameSnapshot: m.name, unitPrice: m.price, quantity: i.quantity };
  });
  const total = subtotal + DELIVERY_FEE;

  const order = await prisma.foodOrder.create({
    data: {
      riderId: user.id,
      restaurantId,
      deliveryAddress,
      subtotal,
      deliveryFee: DELIVERY_FEE,
      total,
      items: { create: orderItems },
    },
    include: { items: true, restaurant: true },
  });
  res.status(201).json(order);
});

// Rider: my food orders (most recent first).
eatsRouter.get("/eats/orders/mine", requireAuth, requireRole("Rider"), async (req, res) => {
  const user = await prisma.user.findUnique({ where: { cognitoSub: req.user!.sub } });
  if (!user) return res.status(404).json({ error: "User not found" });

  const orders = await prisma.foodOrder.findMany({
    where: { riderId: user.id },
    include: { items: true, restaurant: true },
    orderBy: { createdAt: "desc" },
  });
  res.json(orders);
});
