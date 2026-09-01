import 'package:flutter/material.dart';
import 'package:ravelgo_user_app/Model/app_state.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';

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
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        leading: const BackButton(color: AppColors.textPrimary),
        backgroundColor: AppColors.surface,
        elevation: 0,
        centerTitle: true,
        title: const Text("Select a Language", style: TextStyle(color: AppColors.textPrimary)),
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
                final selected = RiderAppState.instance.language == lang["name"];
                return ListTile(
                  leading: Text(lang["flag"]!, style: const TextStyle(fontSize: 20)),
                  title: Text(lang["name"]!),
                  trailing: selected ? const Icon(Icons.check, color: AppColors.success) : null,
                  onTap: () {
                    // LOCAL STATE ONLY: persists the choice for this session;
                    // wiring it into localization delivery is a follow-up.
                    RiderAppState.instance.setLanguage(lang["name"]!);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Language set to ${lang["name"]}')),
                    );
                    Navigator.pop(context, lang["name"]);
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
        border: Border.all(color: AppColors.primary),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.search, color: AppColors.textSecondary),
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
              icon: const Icon(Icons.clear, color: AppColors.textSecondary),
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