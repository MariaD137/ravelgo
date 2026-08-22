import 'package:flutter/material.dart';

class AddressSearch extends StatefulWidget {
  final String addressType; // "Home" or "Work"

  const AddressSearch({super.key, required this.addressType});

  @override
  State<AddressSearch> createState() => _AddressSearchState();
}

class _AddressSearchState extends State<AddressSearch> {
  final TextEditingController _searchController = TextEditingController();
  final List<String> _suggestions = [
    "Denco court 1",
    "Denco court 1",
    "Denco court 1",
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        leading: const BackButton(color: Colors.black),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: Text(widget.addressType, style: const TextStyle(color: Colors.black)),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          children: [
            const SizedBox(height: 10),
            _buildSearchBar(),
            const SizedBox(height: 20),
            _buildLocationTile(
              icon: Icons.home,
              title: "My location",
              subtitle: "",
            ),
            const Divider(),
            ..._suggestions.map((location) => _buildLocationTile(
              icon: Icons.location_on_outlined,
              title: location,
              subtitle: "Kusenla Road, Lekki, Nigeria",
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.yellow[700]!),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const SizedBox(width: 10),
          const Icon(Icons.search, color: Colors.black54),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: 'Denco court 1',
                border: InputBorder.none,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.my_location_outlined, color: Colors.black54),
            onPressed: () {
              // Location fetch logic
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLocationTile({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: Colors.black),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: subtitle.isNotEmpty
          ? Text(subtitle, style: const TextStyle(color: Colors.black54))
          : null,
      onTap: () {
        // Handle selection
      },
    );
  }
}