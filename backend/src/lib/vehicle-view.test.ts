import assert from "node:assert/strict";
import { test } from "node:test";
import { env } from "../config/env";
import { photoUrlFor, serializeVehicle, serializeRentalListing } from "./vehicle-view";

test("photoUrlFor returns null with no photoKey, regardless of CDN config", () => {
  const before = env.ASSETS_CDN_DOMAIN;
  env.ASSETS_CDN_DOMAIN = "cdn.ravelgo.example.com";
  try {
    assert.equal(photoUrlFor(null), null);
    assert.equal(photoUrlFor(undefined), null);
  } finally {
    env.ASSETS_CDN_DOMAIN = before;
  }
});

test("photoUrlFor returns null with a photoKey but no CDN domain configured — never a broken link", () => {
  const before = env.ASSETS_CDN_DOMAIN;
  env.ASSETS_CDN_DOMAIN = undefined;
  try {
    assert.equal(photoUrlFor("some-sub/photo.jpg"), null);
  } finally {
    env.ASSETS_CDN_DOMAIN = before;
  }
});

test("photoUrlFor builds a real https URL from the key and configured CDN domain", () => {
  const before = env.ASSETS_CDN_DOMAIN;
  env.ASSETS_CDN_DOMAIN = "cdn.ravelgo.example.com";
  try {
    assert.equal(photoUrlFor("driver-sub-1/vehicle-photo.jpg"), "https://cdn.ravelgo.example.com/driver-sub-1/vehicle-photo.jpg");
  } finally {
    env.ASSETS_CDN_DOMAIN = before;
  }
});

test("serializeVehicle never includes the raw photoKey", () => {
  const before = env.ASSETS_CDN_DOMAIN;
  env.ASSETS_CDN_DOMAIN = "cdn.ravelgo.example.com";
  try {
    const out = serializeVehicle({
      id: "v1",
      driverId: "d1",
      brand: "Toyota",
      model: "Camry",
      colour: "Silver",
      plateNumber: "ABC-123",
      year: "2021",
      isPrimary: true,
      listedForRental: false,
      photoKey: "driver-sub-1/photo.jpg",
      createdAt: new Date(),
    });
    assert.equal(out.photoUrl, "https://cdn.ravelgo.example.com/driver-sub-1/photo.jpg");
    assert.ok(!("photoKey" in out), "raw photoKey must never leak in the serialized shape");
  } finally {
    env.ASSETS_CDN_DOMAIN = before;
  }
});

test("serializeRentalListing never includes the driver's email or cognitoSub", () => {
  const out = serializeRentalListing({
    id: "l1",
    driverId: "d1",
    vehicleId: "v1",
    dailyRate: 5000,
    location: "Lekki",
    status: "APPROVED",
    createdAt: new Date(),
    vehicle: {
      id: "v1",
      driverId: "d1",
      brand: "Toyota",
      model: "Camry",
      colour: "Silver",
      plateNumber: "ABC-123",
      year: "2021",
      isPrimary: true,
      listedForRental: true,
      photoKey: null,
      createdAt: new Date(),
    },
    driver: { id: "d1", rating: 4.8, user: { firstName: "Ada", lastName: "O" } },
  });
  const raw = JSON.stringify(out);
  assert.ok(!raw.includes("email"));
  assert.ok(!raw.includes("cognitoSub"));
  assert.equal(out.driver?.user?.firstName, "Ada");
});
