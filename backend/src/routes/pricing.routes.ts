import { Router } from "express";
import { z } from "zod";
import { prisma } from "../db/prisma";
import { requireAuth } from "../middleware/auth";
import { requireActiveAdmin, requireAdminPermission } from "../lib/admin-permissions";
import { recordAudit } from "../lib/audit";
import {
  computeFare,
  ensureDefaultRideCategories,
  findActiveSurgeZone,
  quoteAllCategories,
  requireActivePricingRule,
} from "../services/pricing";
import { ensureDefaultDeliveryVehicleRates, quoteAllDeliveryVehicles } from "../services/delivery-pricing";
import {
  getServiceCommissionRate,
  listCommissionConfig,
  setServiceCommissionRate,
} from "../services/commission";
import { getPricingPolicy, PRICING_POLICY_ID } from "../lib/pricing-policy";
import { roundMoney } from "../lib/money";

export const pricingRouter = Router();

// Any authenticated user: browse pricing rules (the app needs these to show
// an estimate before requesting a trip)
pricingRouter.get("/pricing-rules", requireAuth, async (_req, res) => {
  const rules = await prisma.pricingRule.findMany({ orderBy: { createdAt: "desc" } });
  res.json(rules);
});

const createPricingRuleSchema = z.object({
  name: z.string().min(1),
  baseFare: z.number().nonnegative(),
  perKm: z.number().nonnegative(),
  perMinute: z.number().nonnegative(),
});

// Admin: define a pricing rule
pricingRouter.post("/pricing-rules", requireAuth, requireAdminPermission("pricing:write"), async (req, res) => {
  const parsed = createPricingRuleSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const rule = await prisma.pricingRule.create({ data: parsed.data });
  res.status(201).json(rule);
});

const updatePricingRuleSchema = createPricingRuleSchema.partial().extend({
  active: z.boolean().optional(),
});

// Admin: update or (de)activate a pricing rule
pricingRouter.patch("/pricing-rules/:id", requireAuth, requireAdminPermission("pricing:write"), async (req, res) => {
  const parsed = updatePricingRuleSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const rule = await prisma.pricingRule.update({ where: { id: req.params.id }, data: parsed.data });
  res.json(rule);
});

// Any authenticated user: browse surge zones
pricingRouter.get("/surge-zones", requireAuth, async (_req, res) => {
  const zones = await prisma.surgeZone.findMany({ orderBy: { createdAt: "desc" } });
  res.json(zones);
});

const createSurgeZoneSchema = z.object({
  name: z.string().min(1),
  location: z.string().min(1),
  multiplier: z.number().positive(),
  startsAt: z.coerce.date().optional(),
  endsAt: z.coerce.date().optional(),
});

// Admin: define a surge zone
pricingRouter.post("/surge-zones", requireAuth, requireAdminPermission("pricing:write"), async (req, res) => {
  const parsed = createSurgeZoneSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const zone = await prisma.surgeZone.create({ data: parsed.data });
  res.status(201).json(zone);
});

const updateSurgeZoneSchema = createSurgeZoneSchema.partial().extend({
  active: z.boolean().optional(),
});

// Admin: update or (de)activate a surge zone
pricingRouter.patch("/surge-zones/:id", requireAuth, requireAdminPermission("pricing:write"), async (req, res) => {
  const parsed = updateSurgeZoneSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const zone = await prisma.surgeZone.update({ where: { id: req.params.id }, data: parsed.data });
  res.json(zone);
});

const quoteSchema = z.object({
  distanceKm: z.coerce.number().nonnegative(),
  durationMinutes: z.coerce.number().nonnegative(),
  zone: z.string().optional(),
});

// Any authenticated user: get a fare estimate before requesting a trip.
// Uses whichever PricingRule is currently active (there should only be one —
// enforced by convention, not a DB constraint) and, if `zone` matches an
// active SurgeZone by name, multiplies the result.
pricingRouter.get("/pricing/quote", requireAuth, async (req, res) => {
  const parsed = quoteSchema.safeParse(req.query);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const { distanceKm, durationMinutes, zone } = parsed.data;

  // No active rule -> the same 409 as before, surfaced from the shared helper.
  let rule;
  try {
    rule = await requireActivePricingRule();
  } catch {
    return res.status(409).json({ error: "No active pricing rule configured" });
  }
  const surge = await findActiveSurgeZone(zone);
  res.json(computeFare(rule, distanceKm, durationMinutes, surge));
});

// ---------------------------------------------------------------------------
// Ride categories — the multi-tier "Choose your ride" quote + Admin CRUD.
// ---------------------------------------------------------------------------

const categoryQuoteSchema = z.object({
  pickupLat: z.coerce.number().gte(-90).lte(90),
  pickupLng: z.coerce.number().gte(-180).lte(180),
  distanceKm: z.coerce.number().nonnegative(),
  durationMinutes: z.coerce.number().nonnegative(),
  zone: z.string().optional(),
});

// Any authenticated user: a quote for every active ride category on one
// route, for the fare-selection screen. Real availability/pickup-ETA, real
// per-category rate cards — nothing here is a fabricated placeholder price.
pricingRouter.get("/pricing/categories", requireAuth, async (req, res) => {
  const parsed = categoryQuoteSchema.safeParse(req.query);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const { pickupLat, pickupLng, distanceKm, durationMinutes, zone } = parsed.data;
  let quotes;
  try {
    quotes = await quoteAllCategories({ lat: pickupLat, lng: pickupLng }, distanceKm, durationMinutes, zone);
  } catch (err) {
    // One greppable line naming the request (no coordinates — they're the
    // rider's location) before errorHandler logs and maps the error, so a
    // "Fares unavailable" report can be matched to its cause in the logs.
    const e = err as { name?: string; code?: string };
    console.error(
      `[pricing] GET /pricing/categories failed: ${e.name ?? "Error"}${e.code ? ` (${e.code})` : ""} distanceKm=${distanceKm} durationMinutes=${durationMinutes} zone=${zone ?? "-"}`,
    );
    throw err;
  }
  res.json(quotes);
});

// Admin (any preset — reads stay open): every ride category, active or not,
// for the pricing management screen.
pricingRouter.get("/admin/ride-categories", requireAuth, requireActiveAdmin, async (_req, res) => {
  await ensureDefaultRideCategories();
  const categories = await prisma.rideCategory.findMany({ orderBy: { sortOrder: "asc" } });
  res.json(categories);
});

const rideCategoryKeySchema = z
  .string()
  .min(1)
  .max(30)
  .regex(/^[A-Z0-9_]+$/, "key must be upper-case letters, numbers, and underscores only");

const createRideCategorySchema = z.object({
  key: rideCategoryKeySchema,
  name: z.string().min(1),
  description: z.string().min(1),
  benefit: z.string().max(200).optional(),
  baseFare: z.number().nonnegative(),
  perKm: z.number().nonnegative(),
  perMinute: z.number().nonnegative(),
  minimumFare: z.number().nonnegative().default(0),
  // Overrides the RIDE service default (services/commission.ts) for this
  // category only. Omitted = inherit the service-wide rate.
  commissionRate: z.number().min(0).max(1).optional(),
  sortOrder: z.number().int().default(0),
  eligibleVehicleClasses: z.array(z.enum(["ECONOMY", "COMFORT", "PREMIUM", "LUXURY"])).default([]),
});

// Admin: create a ride category.
pricingRouter.post("/admin/ride-categories", requireAuth, requireAdminPermission("pricing:write"), async (req, res) => {
  const parsed = createRideCategorySchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const category = await prisma.rideCategory.create({ data: parsed.data });
  await recordAudit({
    actorSub: req.user!.sub,
    action: "RIDE_CATEGORY_CREATED",
    entityType: "RideCategory",
    entityId: category.id,
    metadata: parsed.data,
  });
  res.status(201).json(category);
});

const updateRideCategorySchema = createRideCategorySchema.partial().extend({ active: z.boolean().optional() });

// Admin: edit, activate/deactivate, reorder, or reconfigure a ride category.
pricingRouter.patch("/admin/ride-categories/:id", requireAuth, requireAdminPermission("pricing:write"), async (req, res) => {
  const parsed = updateRideCategorySchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const existing = await prisma.rideCategory.findUnique({ where: { id: req.params.id } });
  if (!existing) return res.status(404).json({ error: "Ride category not found" });

  const category = await prisma.rideCategory.update({ where: { id: req.params.id }, data: parsed.data });
  await recordAudit({
    actorSub: req.user!.sub,
    action: "RIDE_CATEGORY_UPDATED",
    entityType: "RideCategory",
    entityId: category.id,
    metadata: { changed: parsed.data },
  });
  res.json(category);
});

// ---------------------------------------------------------------------------
// Delivery vehicle rates — the "choose your delivery vehicle" quote + Admin CRUD.
// ---------------------------------------------------------------------------

const deliveryQuoteSchema = z.object({
  distanceKm: z.coerce.number().nonnegative(),
  packageSize: z.enum(["SMALL", "MEDIUM", "LARGE"]).default("MEDIUM"),
});

// Any authenticated user: a quote for every active delivery vehicle class.
pricingRouter.get("/pricing/delivery-quote", requireAuth, async (req, res) => {
  const parsed = deliveryQuoteSchema.safeParse(req.query);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const quotes = await quoteAllDeliveryVehicles(parsed.data.distanceKm, parsed.data.packageSize);
  res.json(quotes);
});

// Admin (any preset — reads stay open): the four delivery vehicle-class rate cards.
pricingRouter.get("/admin/delivery-vehicle-rates", requireAuth, requireActiveAdmin, async (_req, res) => {
  await ensureDefaultDeliveryVehicleRates();
  const rates = await prisma.deliveryVehicleRate.findMany({ orderBy: { initialFee: "asc" } });
  res.json(rates);
});

const DELIVERY_VEHICLE_CLASSES = ["BIKE", "CAR", "SUV", "VAN"] as const;
const updateDeliveryRateSchema = z.object({
  name: z.string().min(1).optional(),
  initialFee: z.number().nonnegative().optional(),
  perKm: z.number().nonnegative().optional(),
  commissionRate: z.number().min(0).max(1).nullable().optional(),
  active: z.boolean().optional(),
});

// Admin: edit one delivery vehicle class's rate card. There are always
// exactly the four reference classes (seeded on first read) — no create/
// delete, matching the pricing spec's fixed Bike/Car/SUV/Van table.
pricingRouter.patch(
  "/admin/delivery-vehicle-rates/:vehicleClass",
  requireAuth,
  requireAdminPermission("pricing:write"),
  async (req, res) => {
    const parsed = updateDeliveryRateSchema.safeParse(req.body);
    if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

    const vehicleClass = req.params.vehicleClass.toUpperCase();
    if (!DELIVERY_VEHICLE_CLASSES.includes(vehicleClass as (typeof DELIVERY_VEHICLE_CLASSES)[number])) {
      return res.status(400).json({ error: "Unknown delivery vehicle class" });
    }
    await ensureDefaultDeliveryVehicleRates();

    const existing = await prisma.deliveryVehicleRate.findUnique({
      where: { vehicleClass: vehicleClass as (typeof DELIVERY_VEHICLE_CLASSES)[number] },
    });
    if (!existing) return res.status(404).json({ error: "Delivery vehicle rate not found" });

    const rate = await prisma.deliveryVehicleRate.update({
      where: { vehicleClass: vehicleClass as (typeof DELIVERY_VEHICLE_CLASSES)[number] },
      data: parsed.data,
    });
    await recordAudit({
      actorSub: req.user!.sub,
      action: "DELIVERY_VEHICLE_RATE_UPDATED",
      entityType: "DeliveryVehicleRate",
      entityId: rate.id,
      metadata: { vehicleClass, changed: parsed.data },
    });
    res.json(rate);
  },
);

// ---------------------------------------------------------------------------
// Commission configuration — the DB-driven replacement for the old hardcoded
// PLATFORM_COMMISSION_RATE constant. Super-Admin only ("settings:write"),
// matching the "Configure commissions" line item admin-permissions.ts's own
// doc comment already anticipated.
// ---------------------------------------------------------------------------

// Admin (any preset — reads stay open): every service's current commission rate.
pricingRouter.get("/admin/commission-config", requireAuth, requireActiveAdmin, async (_req, res) => {
  res.json(await listCommissionConfig());
});

const updateCommissionSchema = z.object({ rate: z.number().min(0).max(1) });

// Admin (Super Admin only): change a service's default commission rate.
// Never affects an already-settled transaction (spec #14) — only
// transactions settled AFTER this change use the new rate.
pricingRouter.patch("/admin/commission-config/:service", requireAuth, requireAdminPermission("settings:write"), async (req, res) => {
  const parsed = updateCommissionSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const service = req.params.service.toUpperCase();
  if (service !== "RIDE" && service !== "DELIVERY") {
    return res.status(400).json({ error: "Unknown service — must be RIDE or DELIVERY" });
  }

  const before = await getServiceCommissionRate(service);
  const updated = await setServiceCommissionRate(service, parsed.data.rate, req.user!.email ?? req.user!.sub);
  await recordAudit({
    actorSub: req.user!.sub,
    action: "COMMISSION_RATE_CHANGED",
    entityType: "CommissionConfig",
    entityId: service,
    metadata: { service, from: before, to: parsed.data.rate },
  });
  res.json(updated);
});

// ---------------------------------------------------------------------------
// Pricing policy — cancellation/waiting/surge-band/package-surcharge config.
// ---------------------------------------------------------------------------

// Admin (any preset — reads stay open): the current policy.
pricingRouter.get("/admin/pricing-policy", requireAuth, requireActiveAdmin, async (_req, res) => {
  res.json(await getPricingPolicy());
});

const updatePricingPolicySchema = z.object({
  rideCancellationGraceSec: z.number().int().nonnegative().optional(),
  rideCancellationFee: z.number().nonnegative().optional(),
  rideWaitingFreeSec: z.number().int().nonnegative().optional(),
  rideWaitingPerMinute: z.number().nonnegative().optional(),
  rideWaitingMaxFee: z.number().nonnegative().optional(),
  deliveryCancellationGraceSec: z.number().int().nonnegative().optional(),
  deliveryCancellationFee: z.number().nonnegative().optional(),
  additionalStopFee: z.number().nonnegative().optional(),
  surgeMinMultiplier: z.number().positive().optional(),
  surgeMaxMultiplier: z.number().positive().optional(),
  packageSizeSurcharge: z.record(z.string(), z.number().nonnegative()).optional(),
});

// Admin (Super Admin only, matching the cash-limit precedent in
// settings.routes.ts): change the cancellation/waiting/surge/package policy.
pricingRouter.patch("/admin/pricing-policy", requireAuth, requireAdminPermission("settings:write"), async (req, res) => {
  const parsed = updatePricingPolicySchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const before = await getPricingPolicy();
  const updated = await prisma.pricingPolicy.upsert({
    where: { id: PRICING_POLICY_ID },
    update: parsed.data,
    create: { id: PRICING_POLICY_ID, ...parsed.data },
  });
  await recordAudit({
    actorSub: req.user!.sub,
    action: "PRICING_POLICY_UPDATED",
    entityType: "PricingPolicy",
    entityId: PRICING_POLICY_ID,
    metadata: { before, changed: parsed.data },
  });
  res.json(updated);
});

// ---------------------------------------------------------------------------
// Admin financial dashboard — the ledger, aggregated (pricing spec #26).
// ---------------------------------------------------------------------------

const dashboardQuerySchema = z.object({
  from: z.coerce.date().optional(),
  to: z.coerce.date().optional(),
});

// Admin (any preset — reads stay open): marketplace-wide financial rollup,
// computed live from the FinancialTransaction ledger — never a cached or
// estimated figure.
pricingRouter.get("/admin/financial-dashboard", requireAuth, requireActiveAdmin, async (req, res) => {
  const parsed = dashboardQuerySchema.safeParse(req.query);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const dateFilter = { gte: parsed.data.from, lte: parsed.data.to };

  // Aggregated at the database level (Postgres GROUP BY / SUM), not by
  // pulling every settled row into Node and summing in JS — the previous
  // implementation had no row cap at all, so a wide date range at real
  // transaction volume was an unbounded-memory query. This computes exact
  // totals over the FULL requested period regardless of how many rows back
  // it, and its cost no longer scales with row count the same way.
  const [byType, cash] = await Promise.all([
    prisma.financialTransaction.groupBy({
      by: ["type"],
      where: { status: "SETTLED", createdAt: dateFilter },
      _sum: { grossAmount: true, commissionAmount: true, driverEarnings: true },
    }),
    prisma.financialTransaction.aggregate({
      where: {
        status: "SETTLED",
        createdAt: dateFilter,
        paymentMethod: "CASH",
        type: { in: ["RIDE_FARE", "DELIVERY_FARE"] },
      },
      _sum: { commissionAmount: true },
    }),
  ]);

  const sums = (type: (typeof byType)[number]["type"]) => byType.find((r) => r.type === type)?._sum;
  const ride = sums("RIDE_FARE");
  const delivery = sums("DELIVERY_FARE");
  const refund = sums("REFUND");
  const cancellation = sums("CANCELLATION_FEE");
  const waiting = sums("WAITING_CHARGE");

  const rideGross = ride?.grossAmount ?? 0;
  const deliveryGross = delivery?.grossAmount ?? 0;
  // REFUND rows store grossAmount as the refunded amount (a positive
  // reduction) and commissionAmount/driverEarnings already negative — same
  // sign convention the previous row-by-row loop relied on.
  const refundGross = refund?.grossAmount ?? 0;

  const grossVolume = rideGross + deliveryGross - refundGross;
  const ravelgoRevenue =
    (ride?.commissionAmount ?? 0) + (delivery?.commissionAmount ?? 0) + (refund?.commissionAmount ?? 0);
  const totalDriverEarnings =
    (ride?.driverEarnings ?? 0) +
    (delivery?.driverEarnings ?? 0) +
    (refund?.driverEarnings ?? 0) +
    (cancellation?.driverEarnings ?? 0) +
    (waiting?.driverEarnings ?? 0);
  const refundsTotal = refundGross;
  const cancellationFeesTotal = cancellation?.grossAmount ?? 0;
  const waitingChargesTotal = waiting?.grossAmount ?? 0;
  const rideRevenue = rideGross;
  const deliveryRevenue = deliveryGross;
  const cashCommissionRecorded = cash._sum.commissionAmount ?? 0;

  res.json({
    grossMarketplaceVolume: roundMoney(grossVolume),
    ravelgoRevenue: roundMoney(ravelgoRevenue),
    driverEarnings: roundMoney(totalDriverEarnings),
    refunds: roundMoney(refundsTotal),
    cancellationFees: roundMoney(cancellationFeesTotal),
    waitingCharges: roundMoney(waitingChargesTotal),
    rideRevenue: roundMoney(rideRevenue),
    deliveryRevenue: roundMoney(deliveryRevenue),
    // Commission recorded against CASH transactions in this window — see
    // GET /admin/cash-reconciliation (cash.routes.ts) for the true
    // outstanding figure net of what drivers have actually remitted.
    cashCommissionRecorded: roundMoney(cashCommissionRecorded),
  });
});
