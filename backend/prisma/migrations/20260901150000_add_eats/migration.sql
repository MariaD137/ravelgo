-- Eats (food delivery) marketplace: restaurants, menus, and orders.

CREATE TYPE "FoodOrderStatus" AS ENUM ('PLACED', 'ACCEPTED', 'PREPARING', 'OUT_FOR_DELIVERY', 'DELIVERED', 'CANCELLED');

CREATE TABLE "Restaurant" (
    "id" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "cuisine" TEXT NOT NULL,
    "imageUrl" TEXT,
    "address" TEXT NOT NULL,
    "isOpen" BOOLEAN NOT NULL DEFAULT true,
    "rating" DOUBLE PRECISION,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Restaurant_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "MenuItem" (
    "id" TEXT NOT NULL,
    "restaurantId" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "description" TEXT,
    "price" DOUBLE PRECISION NOT NULL,
    "imageUrl" TEXT,
    "available" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "MenuItem_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "FoodOrder" (
    "id" TEXT NOT NULL,
    "riderId" TEXT NOT NULL,
    "restaurantId" TEXT NOT NULL,
    "status" "FoodOrderStatus" NOT NULL DEFAULT 'PLACED',
    "subtotal" DOUBLE PRECISION NOT NULL,
    "deliveryFee" DOUBLE PRECISION NOT NULL,
    "total" DOUBLE PRECISION NOT NULL,
    "deliveryAddress" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "FoodOrder_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "FoodOrderItem" (
    "id" TEXT NOT NULL,
    "orderId" TEXT NOT NULL,
    "menuItemId" TEXT NOT NULL,
    "nameSnapshot" TEXT NOT NULL,
    "unitPrice" DOUBLE PRECISION NOT NULL,
    "quantity" INTEGER NOT NULL,

    CONSTRAINT "FoodOrderItem_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "MenuItem_restaurantId_idx" ON "MenuItem"("restaurantId");
CREATE INDEX "FoodOrder_riderId_idx" ON "FoodOrder"("riderId");
CREATE INDEX "FoodOrder_restaurantId_idx" ON "FoodOrder"("restaurantId");
CREATE INDEX "FoodOrderItem_orderId_idx" ON "FoodOrderItem"("orderId");

ALTER TABLE "MenuItem" ADD CONSTRAINT "MenuItem_restaurantId_fkey" FOREIGN KEY ("restaurantId") REFERENCES "Restaurant"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "FoodOrder" ADD CONSTRAINT "FoodOrder_riderId_fkey" FOREIGN KEY ("riderId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "FoodOrder" ADD CONSTRAINT "FoodOrder_restaurantId_fkey" FOREIGN KEY ("restaurantId") REFERENCES "Restaurant"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "FoodOrderItem" ADD CONSTRAINT "FoodOrderItem_orderId_fkey" FOREIGN KEY ("orderId") REFERENCES "FoodOrder"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "FoodOrderItem" ADD CONSTRAINT "FoodOrderItem_menuItemId_fkey" FOREIGN KEY ("menuItemId") REFERENCES "MenuItem"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
