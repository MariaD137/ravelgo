import 'package:flutter/material.dart';



class PostCarScreen extends StatefulWidget {
  const PostCarScreen({super.key});
  @override
  _PostCarScreenState createState() => _PostCarScreenState();
}

class _PostCarScreenState extends State<PostCarScreen> {

  String? selectedFuel;
  String?  selectedMode ;
  String?  selectedSeats;

  @override
  Widget build(BuildContext context) {
    debugPrint('canPop: ${Navigator.of(context).canPop()}'); // should be false
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        centerTitle: true, // 👈 This centers the title
        title: const Text(
          'Post your car',
          style: TextStyle(color: Colors.black),
        ),
        leading: const BackButton(color: Colors.black),
      ),
      body:Container(
    color: Colors.white, // Set background color here
    padding: const EdgeInsets.all(16),
    child:
    SingleChildScrollView(
    child:Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Spacer(),
            ElevatedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.remove_red_eye, size: 16),
              label: const Text('View posts'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.grey,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: const BorderSide(color: Colors.black12),
                ),
              ),
            ),
          ],
        ),
        const Text("Car Reg number"),
        const SizedBox(height: 8),
        TextField(
          decoration: InputDecoration(
            hintText: 'A5678888',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _DropdownTile(
              label: 'Fuel',
              value: selectedFuel,
              options: const ['Petrol', 'Diesel', 'Electric'],
              onChanged: (value) {
                setState(() {
                  selectedFuel = value!;
                });
              },
            )),
            const SizedBox(width: 8),
            Expanded(child: _DropdownTile(
              label: 'Mode',
              value: selectedMode,
              options: const ['Automatic', 'Manual'],
              onChanged: (value) {
                setState(() {
                  selectedMode = value!;
                });
              },
            )),
            const SizedBox(width: 8),
            Expanded(child: _DropdownTile(
              label: 'Seats',
              value: selectedSeats,
              options: const ['4 Seats', '7 Seats', '12 Seats'],
              onChanged: (value) {
                setState(() {
                  selectedSeats = value!;
                });
              },
            )),
          ],
        ),
        const SizedBox(height: 24),
        const UploadSection(title: 'Upload front of your car',showSave: true),
        const SizedBox(height: 24),
        const UploadSection(title: 'Upload Interior of your car',showSave: true),
        const SizedBox(height: 24),
        const UploadSection(title: 'Upload back of your car', showSave: true),
          ],
        ),
       ),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(8),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(double.infinity, 50),
            backgroundColor: Colors.yellow.shade600,
            foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: () {
            // Navigator.of(context).pushAndRemoveUntil(
            //   MaterialPageRoute(builder: (_) => BottomNavigationView()),
            //       (route) => false,
            // );
            Navigator.of(context).popUntil((route) => route.isFirst);
          },
          child: const Text('Done'),
        ),
      ),
    );
  }
}


class _DropdownTile extends StatelessWidget {
  final String label;
  final List<String> options;
  final ValueChanged<String?>? onChanged;
  final String? value;

  const _DropdownTile({
    required this.label,
    required this.options,
    this.onChanged,
    this.value,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      value: value,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
      items: options
          .map((option) => DropdownMenuItem<String>(
        value: option,
        child: Text(option),
      ))
          .toList(),
      onChanged: onChanged,
    );
  }
}

class UploadSection extends StatelessWidget {
  final String title;
  final bool showSave;

  const UploadSection({required this.title, this.showSave = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        const Text(
          'Make sure your photo is clear and unobstructed.',
          style: TextStyle(color: Color(0xFF867804)), // gold-brown style
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.grey.shade200,
                ),
                child: const Icon(Icons.image, size: 32, color: Colors.grey),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Please upload square images',
                      style: TextStyle(
                        fontStyle: FontStyle.italic,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                      height: 50,
                      decoration: BoxDecoration(
                        color: Colors.yellow.shade50,
                      ),
                      child:Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          ElevatedButton(
                            onPressed: () {

                            },
                            style: ElevatedButton.styleFrom(
                              foregroundColor: Colors.black,
                              backgroundColor: Colors.transparent,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                                side: BorderSide(color: Colors.grey.shade400),
                              ),
                            ),
                            child: const Text('Choose File', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                          const Text('No File Chosen', style: TextStyle(fontWeight: FontWeight.w400)),
                        ],
                      )
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}