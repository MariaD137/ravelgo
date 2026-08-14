import 'package:flutter/material.dart';
import 'package:ravelgo/views/HomeView/Home.dart';
class RequestDriverScreen extends StatelessWidget {
  const RequestDriverScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              color: const Color(0xFFD5F4B0),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        "Found 3 Drivers",
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      SizedBox(height: 4),
                      Text(
                        "Pick one, and let’s hit the road",
                        style: TextStyle(fontSize: 13),
                      ),
                    ],
                  ),
              GestureDetector(
                onTap: () {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const HomePage()),
                  );
                },
                child: Text(
                      "Cancel trip",
                      style: TextStyle(
                        color: Colors.redAccent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // Driver list
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: 3,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: DriverCard(),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DriverCard extends StatelessWidget {
  const DriverCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            // Driver row
            Row(
              children: [
                const CircleAvatar(
                  radius: 30,
                  backgroundImage: AssetImage('assets/driver.jpg'), // Replace with your image
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text("Thelma Ibeh",
                          style: TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 16)),
                      SizedBox(height: 2),
                      Text("Toyota Corolla",
                          style: TextStyle(fontSize: 13, color: Colors.black54)),
                      SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(Icons.star, color: Colors.green, size: 16),
                          SizedBox(width: 4),
                          Text("4.55 Rating",
                              style:
                              TextStyle(fontSize: 13, color: Colors.black87)),
                        ],
                      )
                    ],
                  ),
                ),
                const Icon(Icons.verified, color: Colors.amber),
              ],
            ),
            const SizedBox(height: 12),

            // Fare and distance
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: const [
                Text("NGN 7,000",
                    style:
                    TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                Expanded(child: Divider(thickness: 1, color: Colors.black12)),
                Text("10 mins away", style: TextStyle(fontSize: 12)),
              ],
            ),
            const SizedBox(height: 12),

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {},
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.red),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text("Decline",
                        style: TextStyle(color: Colors.red)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {},
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.yellow[700],
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text("Accept"),
                  ),
                )
              ],
            )
          ],
        ),
      ),
    );
  }
}