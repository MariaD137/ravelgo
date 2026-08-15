import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:ravelgo/views/Popup/ColourPicker.dart';
import 'package:ravelgo/views/bottommenu/BottomNavigationView.dart';
import 'AddPhoto.dart';

class VehicleInformationScreen extends StatefulWidget {
  @override
  _VehicleInformationScreenState createState() => _VehicleInformationScreenState();
}

class _VehicleInformationScreenState extends State<VehicleInformationScreen> {
  final _decoration = InputDecoration(
    border: OutlineInputBorder(),
    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
  );

  String? _selectedColorLabel;
  final ImagePicker _picker = ImagePicker();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: Colors.black),
      ),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Vehicle -- Information',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              SizedBox(height: 12),

              /// Vehicle Year
              Text('Vehicle year*'),
              SizedBox(height: 6),
              DropdownButtonFormField<String>(
                items: [DropdownMenuItem(child: Text('2013'), value: '2013')],
                onChanged: (_) {},
                decoration: _decoration,
              ),

              SizedBox(height: 12),

              /// Manufacturer
              Text('Vehicle manufacturer and model*'),
              SizedBox(height: 6),
              DropdownButtonFormField<String>(
                items: [DropdownMenuItem(child: Text('Kia'), value: 'Kia')],
                onChanged: (_) {},
                decoration: _decoration,
              ),

              SizedBox(height: 12),

              /// License Plate
              Text('License Plate*'),
              SizedBox(height: 6),
              TextField(
                decoration: _decoration.copyWith(hintText: 'A5678888'),
              ),

              SizedBox(height: 12),

              /// Color Picker
              Text('Vehicle colour*'),
              SizedBox(height: 6),
              GestureDetector(
                onTap: () async {
                  final result = await showColorPickerPopup(context);
                  if (result != null) {
                    setState(() {
                      _selectedColorLabel = result;
                    });
                  }
                },
                child: AbsorbPointer(
                  child: TextFormField(
                    decoration: _decoration.copyWith(
                      hintText: "Select colour",
                      suffixIcon: Icon(Icons.arrow_drop_down),
                    ),
                    controller: TextEditingController(
                      text: _selectedColorLabel ?? '',
                    ),
                    readOnly: true,
                  ),
                ),
              ),

              SizedBox(height: 18),

              /// Exterior Photo
              Text('Upload Exterior Photo of your vehicle*',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              SizedBox(height: 6),
              Text(
                'Make sure your photos are readable and unobstructed.',
                style: TextStyle(color: Colors.green, fontSize: 12),
              ),
              SizedBox(height: 12),
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(children: [
                  SizedBox(
                      width: 80,
                      height: 80,
                      child: localImage(
                        '/mnt/data/Vehicle_information.png',
                        fit: BoxFit.cover,
                      )),
                  SizedBox(width: 12),
                  ElevatedButton(
                      onPressed: ()  async {
                        final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
                        if (image != null) {
                          print("Selected file: ${image.path}");
                          // handle the selected image file here
                        }
                      }, child: Text('Choose File')),
                ]),
              ),

              SizedBox(height: 12),

              /// Interior Photo
              Text('Upload Interior photo of your vehicle*',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              SizedBox(height: 8),
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(children: [
                  SizedBox(
                      width: 80,
                      height: 80,
                      child: localImage(
                        '/mnt/data/Vehicle_information.png',
                        fit: BoxFit.cover,
                      )),
                  SizedBox(width: 12),
                  ElevatedButton(
                      onPressed: ()   async {
                        final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
                        if (image != null) {
                          print("Selected file: ${image.path}");
                          // handle the selected image file here
                        }
                      }, child: Text('Choose File')),
                ]),
              ),

              SizedBox(height: 30),

              /// Submit Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.push(context,
                      MaterialPageRoute(builder: (context) => BottomNavigationView()),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.yellow[700],
                    foregroundColor: Colors.black,
                  ),
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('Submit'),
                  ),
                ),
              ),

              SizedBox(height: 18),
            ],
          ),
        ),
      ),
    );
  }
}

