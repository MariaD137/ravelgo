import 'package:flutter/material.dart';
import 'package:ravelgo_user_app/views/Driver_Portal/side_menu_driver.dart';

class MyDocumentsScreen extends StatefulWidget {
  const MyDocumentsScreen({Key? key}) : super(key: key);

  @override
  State<MyDocumentsScreen> createState() => _MyDocumentsScreenState();
}

class _MyDocumentsScreenState extends State<MyDocumentsScreen> {
  String? year;
  String? month;
  String? day;

  final years = List.generate(10, (i) => (2024 + i).toString());
  final months = List.generate(12, (i) => (i + 1).toString());
  final days = List.generate(31, (i) => (i + 1).toString());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const SideMenuDriver(initialSelectedItem: "My Document",),
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              /// HEADER
              Row(
                children: [
                  Builder(
                    builder: (context) {
                      return GestureDetector(
                        onTap: () {
                          Scaffold.of(context).openDrawer();
                        },
                        child: Container(
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(color: Colors.black12, blurRadius: 6),
                            ],
                          ),
                          child: const CircleAvatar(
                            backgroundColor: Colors.white,
                            child: Icon(Icons.menu, color: Colors.black),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 16),
                  Image.asset(
                    "assets/ravel_go_driver_badge.png",
                    height: 28,
                  ),
                ],
              ),

              const SizedBox(height: 28),

              /// TITLE
              const Text(
                "My Documents",
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              const Text(
                "These are the documents linked to your driver profile.",
                style: TextStyle(fontSize: 15, color: Colors.black54),
              ),

              const SizedBox(height: 24),

              /// DRIVER LICENSE CARD
              _documentCard(
                title: "Driver’s license",
                description:
                "Make sure your photos are readable and unobstructed. It should contain the document number, your name, an date of birth",
                showExpiryForm: true,
              ),

              const SizedBox(height: 20),

              /// PROFILE PHOTO CARD
              _documentCard(
                title: "Driver’s profile photo",
                description:
                "Please upload a clear, front-view portrait of yourself, making sure your whole face is visible and your eyes are open. Full-body pictures are not accepted.",
              ),

              const SizedBox(height: 20),

              /// NIN SLIP CARD
              _documentCard(
                title: "NIN Slip",
                description:
                "Make sure your photos are readable and unobstructed. It should contain the document number, your name, an date of birth",
                required: true,
              ),

              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _documentCard({
    required String title,
    required String description,
    bool showExpiryForm = false,
    bool required = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFFFD500), width: 2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          /// TITLE ROW
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
              ),
              if (required)
                const Text(
                  "Required*",
                  style: TextStyle(
                      color: Colors.red, fontWeight: FontWeight.w600),
                ),
            ],
          ),

          const SizedBox(height: 12),

          Text(
            description,
            style: const TextStyle(color: Colors.black54),
          ),

          const SizedBox(height: 24),

          const Text(
            "Verified document",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),

          const SizedBox(height: 10),

          const Text(
            "Image.png",
            style: TextStyle(
                color: Color(0xFFB58B00), fontWeight: FontWeight.w500),
          ),

          const SizedBox(height: 16),

          _infoRow("Uploaded:", "15/06/2024"),
          const SizedBox(height: 6),
          _infoRow("Expires:", "15/06/2028"),

          if (showExpiryForm) ...[
            const SizedBox(height: 28),

            const Text(
              "Expires",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),

            const SizedBox(height: 14),

            _dropdown("Year", "Enter Year", year, years,
                    (v) => setState(() => year = v)),
            const SizedBox(height: 16),
            _dropdown("Month", "Enter Month", month, months,
                    (v) => setState(() => month = v)),
            const SizedBox(height: 16),
            _dropdown("Day", "Enter Day", day, days,
                    (v) => setState(() => day = v)),
          ],

          const SizedBox(height: 20),

          /// UPLOAD BOX
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(Icons.image_outlined,
                      size: 30, color: Colors.grey),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Please upload square images",
                        style: TextStyle(fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5E9C5),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Text("Choose File"),
                            SizedBox(width: 8),
                            Text("Image",
                                style: TextStyle(color: Colors.black54)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Row(
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        const Spacer(),
        Text(value),
      ],
    );
  }

  Widget _dropdown(String label, String hint, String? value,
      List<String> items, Function(String?) onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style:
            const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: value,
          hint: Text(hint),
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            contentPadding:
            EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          ),
          items: items
              .map((e) => DropdownMenuItem(value: e, child: Text(e)))
              .toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }
}