import 'package:flutter/material.dart';

class BasicDetailsPage extends StatefulWidget {
  const BasicDetailsPage({super.key});

  @override
  State<BasicDetailsPage> createState() => _BasicDetailsPageState();
}

class _BasicDetailsPageState extends State<BasicDetailsPage> {
  bool obscurePin = true;
  bool obscureConfirmPin = true;

  String fileName = "No File Chosen";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFFFF),
      body: SafeArea(
        child: Column(
          children: [

            /// HEADER
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Icon(Icons.arrow_back),
                ),
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    /// PROFILE ICON
                    Center(
                      child: Stack(
                        children: [
                          Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade300,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.person_outline, size: 30),
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: const BoxDecoration(
                                color: Color(0xFFFFD500),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.edit, size: 14),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    /// PIN LABEL
                    const Text(
                      "Enter 6 digit security pin",
                      style: TextStyle(fontSize: 14),
                    ),

                    const SizedBox(height: 6),

                    _inputField(obscurePin, () {
                      setState(() => obscurePin = !obscurePin);
                    }),

                    const SizedBox(height: 16),

                    /// CONFIRM PIN
                    const Text(
                      "Confirm pin",
                      style: TextStyle(fontSize: 14),
                    ),

                    const SizedBox(height: 6),

                    _inputField(obscureConfirmPin, () {
                      setState(() => obscureConfirmPin = !obscureConfirmPin);
                    }),

                    const SizedBox(height: 20),

                    /// TITLE
                    const Text(
                      "Upload an image of your ID",
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),

                    const SizedBox(height: 6),

                    /// DESCRIPTION
                    const Text(
                      "Acceptable form of ID include: NIN, driver’s license, passport or voters card. Make sure your photos are readable and unobstructed.",
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                        height: 1.4,
                      ),
                    ),

                    const SizedBox(height: 12),

                    /// UPLOAD BOX (MATCHED DESIGN)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade300),
                        color: Colors.white,
                      ),
                      child: Row(
                        children: [

                          /// LEFT IMAGE BOX
                          Container(
                            width: 70,
                            height: 70,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.image_outlined),
                          ),

                          const SizedBox(width: 12),

                          /// RIGHT CONTENT
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [

                                const Text(
                                  "Please upload square images",
                                  style: TextStyle(fontSize: 12),
                                ),

                                const SizedBox(height: 8),

                                Row(
                                  children: [

                                    /// CHOOSE FILE BUTTON
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 8),
                                      decoration: BoxDecoration(
                                        border: Border.all(color: Colors.blue),
                                        borderRadius: BorderRadius.circular(6),
                                        color: Colors.blue.shade50,
                                      ),
                                      child: const Text(
                                        "Choose File",
                                        style: TextStyle(color: Colors.blue),
                                      ),
                                    ),

                                    const SizedBox(width: 10),

                                    Expanded(
                                      child: Text(
                                        fileName,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 30),

                    /// DONE BUTTON
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: () {
                            Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFFD500),
                          foregroundColor: Colors.black,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          "Done",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// INPUT FIELD (PERFECT STYLE)
  Widget _inputField(bool obscure, VoidCallback onToggle) {
    return TextField(
      obscureText: obscure,
      keyboardType: TextInputType.number,
      maxLength: 6,
      decoration: InputDecoration(
        counterText: "",
        filled: true,
        fillColor: Colors.white,
        contentPadding:
        const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        suffixIcon: IconButton(
          icon: Icon(
            obscure ? Icons.visibility_off : Icons.visibility,
            color: Colors.grey,
          ),
          onPressed: onToggle,
        ),
      ),
    );
  }
}