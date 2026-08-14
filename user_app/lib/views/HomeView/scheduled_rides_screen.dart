import 'package:flutter/material.dart';
import 'package:ravelgo/components/ride_controller.dart';

class ScheduledRidesRequestsScreen extends StatefulWidget {
  const ScheduledRidesRequestsScreen({Key? key}) : super(key: key);

  @override
  State<ScheduledRidesRequestsScreen> createState() =>
      _ScheduledRidesRequestsScreenState();
}

class _ScheduledRidesRequestsScreenState
    extends State<ScheduledRidesRequestsScreen> {
  int selectedIndex = 0; // 0 = Requests, 1 = Confirmed
  bool hasRequests = false;
  bool hasConfirm = false;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            children: [

              /// TOP BAR
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back),
                  ),
                  const Expanded(
                    child: Center(
                      child: Text(
                        "Scheduled Rides requests",
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(width: 48), // balance arrow space
                ],
              ),

              const SizedBox(height: 20),

              /// SEGMENTED TAB
              Container(
                height: 48,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    _buildTab("Requests", 0),
                    _buildTab("Confirmed", 1),
                  ],
                ),
              ),

              const SizedBox(height: 40),

              /// BODY
              Expanded(
                child: Center(
                  child: selectedIndex == 0
                      ? hasRequests == true ? _emptyRequests() : ListView(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                              children: const [
                                      RideRequestCard(),
                                      SizedBox(height: 40),
                                      RideRequestCard(),
                                  ],
                              )
                      : hasConfirm == true ? _emptyConfirmed() : ListView.separated(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                              itemCount: 3,
                              separatorBuilder: (_, __) => const SizedBox(height: 25),
                              itemBuilder: (context, index) {
                                return const RideBorderCard();
                              },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTab(String title, int index) {
    final bool isSelected = selectedIndex == index;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            selectedIndex = index;
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: isSelected
                  ? const Color(0xFF6B5A00)
                  : Colors.black54,
            ),
          ),
        ),
      ),
    );
  }

  Widget _emptyRequests() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: const [
        Text(
          "No scheduled rides available",
          style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.w600),
        ),
        SizedBox(height: 10),
        Text(
          "A list of scheduled rides available for booking will be displayed here",
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.black54),
        ),
      ],
    );
  }

  Widget _emptyConfirmed() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: const [
        Text(
          "No rides accepted",
          style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.w600),
        ),
        SizedBox(height: 10),
        Text(
          "All confirmed requests will be shown here",
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.black54),
        ),
      ],
    );
  }
}
class RideRequestCard extends StatelessWidget {
  const RideRequestCard({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    const goldColor = Color(0xFFFFD700);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        /// Date & Time
        const Text(
          "Tomorrow, 30 Mar, 14:30",
          style: TextStyle(
            color: Color(0xFF665600),
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),

        const SizedBox(height: 15),

        /// Route Label
        const Text(
          "Route",
          style: TextStyle(
            color: Colors.black,
            fontSize: 14,
          ),
        ),

        const SizedBox(height: 12),

        /// Pickup
        Row(
          children: [
            Image.asset("assets/trip_origin.png",width: 14,height: 14,),
            SizedBox(width: 10),
            Text(
              "Denco court 1",
              style: TextStyle(
                color: Colors.black,
                fontSize: 15,
              ),
            ),
          ],
        ),

        const SizedBox(height: 10),

        /// Destination
        Row(
          children: const [
            Icon(Icons.location_on, size: 18, color: goldColor),
            SizedBox(width: 10),
            Text(
              "Destination",
              style: TextStyle(
                color: Colors.black,
                fontSize: 15,
              ),
            ),
          ],
        ),

        const SizedBox(height: 20),

        /// Fare
        RichText(
          text: const TextSpan(
            children: [
              TextSpan(
                text: "Delivery fare: ",
                style: TextStyle(
                  color: Color(0xFF665600),
                  fontSize: 14,
                ),
              ),
              TextSpan(
                text: "NGN 8,000",
                style: TextStyle(
                  color: Color(0xFF665600),
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 25),

        /// Buttons Row
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: goldColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () {
                      RideController.startRide();
                      Navigator.pop(context); // optional
                  },
                  child: const Text(
                    "Accept",
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: SizedBox(
                height: 50,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    backgroundColor: Colors.white,
                    side: const BorderSide(
                      color: Colors.red,
                      width: 1.5,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () {},
                  child: const Text(
                    "Decline",
                    style: TextStyle(
                      color: Colors.red,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
class RideBorderCard extends StatelessWidget {
  const RideBorderCard({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFFFFD700);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: gold, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          /// Date
          const Text(
            "Tomorrow, 30 Mar, 14:30",
            style: TextStyle(
              color: Color(0xFF665600),
              fontSize: 16,
              fontWeight: FontWeight.normal,
            ),
          ),

          const SizedBox(height: 18),

          /// Route Label
          const Text(
            "Route",
            style: TextStyle(
              color: Colors.black,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 15),

          /// Pickup
          Row(
            children:  [
              Image.asset("assets/trip_origin.png",width: 14,height: 14,),
              SizedBox(width: 12),
              Text(
                "Denco court 1",
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 15,
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          /// Destination
          Row(
            children: const [
              Icon(Icons.location_on,
                  size: 20, color: gold),
              SizedBox(width: 12),
              Text(
                "Destination",
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 15,
                ),
              ),
            ],
          ),

          const SizedBox(height: 25),

          /// Fare
          RichText(
            text: const TextSpan(
              children: [
                TextSpan(
                  text: "Estimated fare: ",
                  style: TextStyle(
                    color: Color(0xFF665600),
                    fontSize: 14,
                  ),
                ),
                TextSpan(
                  text: "NGN 8,000",
                  style: TextStyle(
                    color: Color(0xFF665600),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}