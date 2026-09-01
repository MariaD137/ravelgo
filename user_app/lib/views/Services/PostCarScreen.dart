import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';



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
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        centerTitle: true, // 👈 This centers the title
        title: const Text(
          'Post your car',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        leading: const BackButton(color: AppColors.textPrimary),
      ),
      body:Container(
    color: AppColors.surface, // Set background color here
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
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("You haven't posted any cars yet")),
                );
              },
              icon: const Icon(Icons.remove_red_eye, size: 16),
              label: const Text('View posts'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.surface,
                foregroundColor: AppColors.textMuted,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: const BorderSide(color: AppColors.border),
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
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.textPrimary,
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

class UploadSection extends StatefulWidget {
  final String title;
  final bool showSave;

  const UploadSection({required this.title, this.showSave = false});

  @override
  State<UploadSection> createState() => _UploadSectionState();
}

class _UploadSectionState extends State<UploadSection> {
  final ImagePicker _picker = ImagePicker();
  XFile? _file;

  Future<void> _chooseFile() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null && mounted) {
      setState(() => _file = image);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.title,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        const Text(
          'Make sure your photo is clear and unobstructed.',
          style: TextStyle(color: AppColors.primaryDark), // gold-brown style
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: AppColors.surfaceElevated,
                ),
                child: const Icon(Icons.image, size: 32, color: AppColors.textMuted),
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
                        color: AppColors.primaryTint,
                      ),
                      child:Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          ElevatedButton(
                            onPressed: _chooseFile,
                            style: ElevatedButton.styleFrom(
                              foregroundColor: AppColors.textPrimary,
                              backgroundColor: Colors.transparent,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                                side: BorderSide(color: AppColors.border),
                              ),
                            ),
                            child: const Text('Choose File', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                          Expanded(
                            child: Text(
                              _file == null ? 'No File Chosen' : _file!.name,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.end,
                              style: const TextStyle(fontWeight: FontWeight.w400),
                            ),
                          ),
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