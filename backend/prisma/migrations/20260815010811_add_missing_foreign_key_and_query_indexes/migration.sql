-- CreateIndex
CREATE INDEX "CarPaddyRequest_driverId_idx" ON "CarPaddyRequest"("driverId");

-- CreateIndex
CREATE INDEX "CourierRequest_senderId_idx" ON "CourierRequest"("senderId");

-- CreateIndex
CREATE INDEX "CourierRequest_driverId_idx" ON "CourierRequest"("driverId");

-- CreateIndex
CREATE INDEX "CourierRequest_status_idx" ON "CourierRequest"("status");

-- CreateIndex
CREATE INDEX "Driver_status_idx" ON "Driver"("status");

-- CreateIndex
CREATE INDEX "DriverDocument_driverId_idx" ON "DriverDocument"("driverId");

-- CreateIndex
CREATE INDEX "DriverSubscription_planId_idx" ON "DriverSubscription"("planId");

-- CreateIndex
CREATE INDEX "EmergencyAlert_userId_idx" ON "EmergencyAlert"("userId");

-- CreateIndex
CREATE INDEX "EmergencyAlert_tripId_idx" ON "EmergencyAlert"("tripId");

-- CreateIndex
CREATE INDEX "Payment_userId_idx" ON "Payment"("userId");

-- CreateIndex
CREATE INDEX "Payment_providerReference_idx" ON "Payment"("providerReference");

-- CreateIndex
CREATE INDEX "RentalListing_driverId_idx" ON "RentalListing"("driverId");

-- CreateIndex
CREATE INDEX "RentalListing_vehicleId_idx" ON "RentalListing"("vehicleId");

-- CreateIndex
CREATE INDEX "SupportTicket_userId_idx" ON "SupportTicket"("userId");

-- CreateIndex
CREATE INDEX "Trip_riderId_idx" ON "Trip"("riderId");

-- CreateIndex
CREATE INDEX "Trip_driverId_idx" ON "Trip"("driverId");

-- CreateIndex
CREATE INDEX "Trip_status_idx" ON "Trip"("status");

-- CreateIndex
CREATE INDEX "User_role_idx" ON "User"("role");

-- CreateIndex
CREATE INDEX "Vehicle_driverId_idx" ON "Vehicle"("driverId");
