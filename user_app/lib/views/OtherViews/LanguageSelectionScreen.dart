import 'package:flutter/material.dart';

class LanguageSelectionScreen extends StatefulWidget {
  const LanguageSelectionScreen({super.key});

  @override
  State<LanguageSelectionScreen> createState() => _LanguageSelectionScreenState();
}

class _LanguageSelectionScreenState extends State<LanguageSelectionScreen> {
  final TextEditingController _searchController = TextEditingController();
  final List<Map<String, String>> _allLanguages = [
    {"name": "Arabic", "flag": "🇸🇦"},
    {"name": "Bengali", "flag": "🇧🇩"},
    {"name": "English", "flag": "🇬🇧"},
    {"name": "French", "flag": "🇫🇷"},
    {"name": "German", "flag": "🇩🇪"},
    {"name": "Hindi", "flag": "🇮🇳"},
    {"name": "Italian", "flag": "🇮🇹"},
    {"name": "Japanese", "flag": "🇯🇵"},
    {"name": "Javanese", "flag": "🇮🇩"},
    {"name": "Korean", "flag": "🇰🇷"},
    {"name": "Marathi", "flag": "🇮🇳"},
    {"name": "Portuguese", "flag": "🇵🇹"},
    {"name": "Russian", "flag": "🇷🇺"},
    {"name": "Spanish", "flag": "🇪🇸"},
    {"name": "Swahili", "flag": "🇰🇪"},
    {"name": "Tamil", "flag": "🇮🇳"},
    {"name": "Telugu", "flag": "🇮🇳"},
    {"name": "Turkish", "flag": "🇹🇷"},
  ];

  List<Map<String, String>> _filteredLanguages = [];

  @override
  void initState() {
    super.initState();
    _filteredLanguages = _allLanguages;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterLanguages(String query) {
    final lowerQuery = query.toLowerCase();
    setState(() {
      _filteredLanguages = _allLanguages
          .where((lang) => lang["name"]!.toLowerCase().contains(lowerQuery))
          .toList();
    });
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
        title: const Text("Select a Language", style: TextStyle(color: Colors.black)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: _buildSearchBar(),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _filteredLanguages.length,
              itemBuilder: (context, index) {
                final lang = _filteredLanguages[index];
                return ListTile(
                  leading: Text(lang["flag"]!, style: const TextStyle(fontSize: 20)),
                  title: Text(lang["name"]!),
                  onTap: () {
                    // Handle language selection
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.yellow[700]!),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.search, color: Colors.black54),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: "Search your language",
                border: InputBorder.none,
              ),
              onChanged: _filterLanguages,
            ),
          ),
          if (_searchController.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear, color: Colors.black45),
              onPressed: () {
                _searchController.clear();
                _filterLanguages('');
              },
            ),
        ],
      ),
    );
  }
}