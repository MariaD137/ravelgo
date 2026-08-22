import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:ravelgo_rider_app/views/Signup/VehicleInformation.dart';

class AddPhotoScreen extends StatelessWidget {
  final ImagePicker _picker = ImagePicker();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0, iconTheme: IconThemeData(color: Colors.black)),
      body: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          children: [
            Text('Add Photo', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            SizedBox(height: 18),
            Container(
              decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(12)),
              padding: EdgeInsets.all(18),
              child: Column(
                children: [
                  ClipRRect(borderRadius: BorderRadius.circular(12), child: SizedBox(height: 180, width: 180, child: localImage('/mnt/data/Add_photo.png', fit: BoxFit.cover))),
                  SizedBox(height: 12),
                  OutlinedButton(onPressed: ()  async {
                    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
                    if (image != null) {
                      print("Selected file: ${image.path}");
                      // handle the selected image file here
                    }
                  }, child: Text('Add a photo')),
                  SizedBox(height: 12),
                  Text('Please upload a clear, front-view portrait of yourself, making sure your whole face is visible and your eyes are open. Full-body pictures are not accepted.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[700])),
                ],
              ),
            ),
            Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => {
                  Navigator.push(context,
                    MaterialPageRoute(builder: (context) => VehicleInformationScreen()),
                  )
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.yellow[700], foregroundColor: Colors.black),
                child: Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Text('Next')),
              ),
            ),
            SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}

// Simple helper to load an image from the provided local path.
Widget localImage(String path, {BoxFit fit = BoxFit.contain}) {
  final file = File(path);
  return file.existsSync()
      ? Image.file(file, fit: fit)
      : Container(
    color: Colors.grey[200],
    child: Center(child: Icon(Icons.image, size: 60, color: Colors.grey[400])),
  );
}
