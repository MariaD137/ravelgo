import 'package:flutter/material.dart';

class SupportView extends StatelessWidget {
  const SupportView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(70),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(24),
              bottomRight: Radius.circular(24),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: const [
                  BackButton(color: Colors.black),
                  Spacer(),
                  Text(
                    'Payment',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.normal, color: Colors.black),
                  ),
                  Spacer(),
                  SizedBox(width: 64)
                ],
              ),
            ),
          ),
        ),
      ),
      backgroundColor: Colors.white,
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          const Text(
            'Do you need help with  trips?',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 12),

          // Recent trips header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            color: Colors.grey.shade200,
            child: const Text('Your Recent trips'),
          ),

          // Trip items
          ...List.generate(3, (index) {
            return ListTile(
              dense: true,
              title: const Text("Yesterday, 18:45"),
              trailing: const Text("#1500", style: TextStyle(color: Colors.grey)),
              onTap: () {},
              contentPadding: EdgeInsets.zero,
            );
          }),

          // View all trips
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () {},
              child: const Text(
                "View all trips",
                style: TextStyle(color: Colors.green),
              ),
            ),
          ),

          const SizedBox(height: 16),
          const Text(
            'Do you need help with something else?',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 12),

          // Help Categories
          _helpCategoryTile('Get help with something else'),
          _helpCategoryTile('About  Ravel Go'),
          _helpCategoryTile('Ride booking issues'),
          _helpCategoryTile('Pricing and payments'),
          _helpCategoryTile('Ride experience & safety'),
          _helpCategoryTile('Lost & Found'),
          _helpCategoryTile('App and account issue'),
        ],
      ),
    );
  }

  Widget _helpCategoryTile(String label) {
    return Column(
      children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 0),
          title: Text(label),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            debugPrint("Tapped: $label");
          },
        ),
        const Divider(height: 1),
      ],
    );
  }
}