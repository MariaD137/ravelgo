import 'package:flutter/material.dart';
import 'package:ravelgo_user_app/components/RideOptionCard.dart';
import 'package:ravelgo_user_app/views//Services/CarRentalScreen.dart';
import 'package:ravelgo_user_app/views/Services/IdelivaOnboardingScreen.dart';
import 'package:ravelgo_user_app/components/RideOptionCard.dart';
import 'package:ravelgo_user_app/views/TexiModule/FindRoute.dart';

class ServicesView extends StatefulWidget {
  const ServicesView({super.key});

  @override
  State<ServicesView> createState() => _ServicesViewSelectorState();
}

class _ServicesViewSelectorState extends State<ServicesView> {
  int selectedIndex = -1;

  void onCardTapped(int index) {
    setState(() {
      selectedIndex = index;
      switch (index) {
        case 0:
          Navigator.of(context).push(
            MaterialPageRoute(builder: (context) => FindRouteScreen()),
          );
          break;
        case 1:
          Navigator.of(context).push(
            MaterialPageRoute(builder: (context) => CarRentalScreen()),
          );
          break;
        case 2:
          Navigator.of(context).push(
            MaterialPageRoute(builder: (context) => IdelivaOnboardingScreen()),
          );
          break;
        default:
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea( // ✅ helps on iOS with notch/safe area
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              const Text(
                "Our services",
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              const Text(
                "Your ride, your way - anything delivered",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 20),

              // Ride Card
              Container(
                width: double.infinity,
                height: 160,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.black, width: 2.0),
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.all(20),
                child: RideOptionCard(
                  label: 'Ride',
                  iconPath: 'assets/ic_ride.png',
                  isSelected: selectedIndex == 0,
                  onTap: () => onCardTapped(0),
                ),
              ),

              const SizedBox(height: 20),

              // Rental + i-deliva
              Container(
                width: double.infinity,
                height: 160,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.black, width: 2.0),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: RideOptionCard(
                        label: 'Rental',
                        iconPath: 'assets/ic_rent_car.png',
                        isSelected: selectedIndex == 1,
                        onTap: () => onCardTapped(1),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: RideOptionCard(
                        label: 'i-deliva',
                        iconPath: 'assets/ic_ideliva.png',
                        isSelected: selectedIndex == 2,
                        onTap: () => onCardTapped(2),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}