import 'package:flutter/material.dart';
import 'package:ravelgo_rider_app/views/AccountView/Account.dart';
import 'package:ravelgo_rider_app/views/Driver_Portal/contact_us_screen.dart';
import 'package:ravelgo_rider_app/views/Driver_Portal/faq_screen.dart';
import 'package:ravelgo_rider_app/views/Driver_Portal/my_documents_view.dart';
import 'package:ravelgo_rider_app/views/Driver_Portal/my_trips_view.dart';
import 'package:ravelgo_rider_app/views/Driver_Portal/passenger_invoice_screen.dart';
import 'package:ravelgo_rider_app/views/Driver_Portal/ravel_driver_portal_screen.dart';
import 'package:ravelgo_rider_app/views/Driver_Portal/vehicle_list_screen.dart';
class SideMenuDriver extends StatefulWidget {
  final String initialSelectedItem;

  const SideMenuDriver({
    Key? key,
    this.initialSelectedItem = "My Profile",
  }) : super(key: key);

  @override
  State<SideMenuDriver> createState() => _SideMenuDriverState();
}

class _SideMenuDriverState extends State<SideMenuDriver> {
  late String selectedItem;

  @override
  void initState() {
    super.initState();
    selectedItem = widget.initialSelectedItem;
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: Colors.white,
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 20),
            _menuItem(
              context,
              icon: Icons.person_outline,
              label: "My Profile",
              onTap: () {
                setState(() => selectedItem = "My Profile");

                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const RavelDriverPortalScreen(),
                  ),
                );
              },
            ),

            _menuItem(
              context,
              icon: Icons.description_outlined,
              label: "My Document",
              onTap: () {
                setState(() => selectedItem = "My Document");

                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const MyDocumentsScreen(),
                  ),
                );
              },
            ),

            _menuItem(
              context,
              icon: Icons.list_alt_outlined,
              label: "My Trips",
              onTap: () {
                setState(() => selectedItem = "My Trips");

                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const MyTripsScreen(),
                  ),
                );
              },
            ),

            _menuItem(
              context,
              icon: Icons.directions_car_outlined,
              label: "Vehicles",
              onTap: () {
                setState(() => selectedItem = "Vehicles");

                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const VehicleListScreen(),
                  ),
                );
              },
            ),

            _menuItem(
              context,
              icon: Icons.receipt_long_outlined,
              label: "Passenger Invoices",
              onTap: () {
                setState(() => selectedItem = "Passenger Invoices");

                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const PassengerInvoiceScreen(),
                  ),
                );
              },
            ),

            _menuItem(
              context,
              icon: Icons.help_outline,
              label: "FAQ",
              onTap: () {
                setState(() => selectedItem = "FAQ");

                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>  FAQScreen(),
                  ),
                );
              },
            ),

            _menuItem(
              context,
              icon: Icons.phone_outlined,
              label: "Contacts",
              onTap: () {
                setState(() => selectedItem = "Contacts");

                Navigator.pop(context);
                  Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>  ContactUsScreen(),
                        ),
                      );
              },
            ),

            _menuItem(
              context,
              icon: Icons.logout,
              label: "Go To App",
              onTap: () {
                setState(() => selectedItem = "Go To App");

                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const Accountview(),
                  ),
                );

              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _menuItem(
      BuildContext context, {
        required IconData icon,
        required String label,
        VoidCallback? onTap,
      }) {
    final bool isSelected = selectedItem == label;

    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        color:
        isSelected ? const Color(0xFFFFF4C2) : Colors.transparent,
        child: Row(
          children: [
            Icon(icon,
                size: 22,
                color: isSelected ? Colors.black : Colors.black87),
            const SizedBox(width: 16),
            Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color:
                isSelected ? Colors.black : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }
}