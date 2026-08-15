import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CommunicationTogglePage extends StatefulWidget {
  final String title;

  const CommunicationTogglePage({super.key, required this.title});

  @override
  State<CommunicationTogglePage> createState() =>
      _CommunicationTogglePageState();
}

class _CommunicationTogglePageState
    extends State<CommunicationTogglePage> {

  final Map<String, bool> settings = {
    "E-mail": false,
    "Push": false,
    "SMS": false,
    "APP Inbox": false,
    "Voice calls": false,
    "Whatsapp": false,
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F6),
      body: SafeArea(
        child: Column(
          children: [

            /// HEADER
            Padding(
              padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.arrow_back),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    widget.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),

            /// CONTENT
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [

                    /// CARD
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: _buildTiles(),
                      ),
                    ),

                    /// LINE BELOW CARD
                    Container(
                      height: 1,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      color: Colors.grey.shade300,
                    ),

                    const Spacer(),
                  ],
                ),
              ),
            ),

            /// SAVE BUTTON
            Container(
              padding:
              const EdgeInsets.fromLTRB(16, 10, 16, 16),
              decoration: const BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 10,
                    offset: Offset(0, -3),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () async {
                      final prefs = await SharedPreferences.getInstance();
                      for (final entry in settings.entries) {
                        await prefs.setBool('comm_${widget.title}_${entry.key}', entry.value);
                      }
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Settings saved')),
                      );
                      Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFD500),
                      foregroundColor: Colors.black,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      "Save",
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// BUILD TOGGLES
  List<Widget> _buildTiles() {
    final keys = settings.keys.toList();

    return List.generate(keys.length, (index) {
      final key = keys[index];

      return Column(
        children: [
          Padding(
            padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    key,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),

                /// SWITCH
                Switch(
                  value: settings[key]!,
                  onChanged: (value) {
                    setState(() {
                      settings[key] = value;
                    });
                  },
                  activeColor: const Color(0xFFFFD500),
                ),
              ],
            ),
          ),

          /// DIVIDER
          if (index != keys.length - 1)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Divider(
                height: 1,
                thickness: 1,
                color: Colors.grey.shade300,
              ),
            ),
        ],
      );
    });
  }
}