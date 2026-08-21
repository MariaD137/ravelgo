import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'add_photo.dart';

class DriverInformationScreen extends StatelessWidget {
  final _decoration = InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 16));
  final ImagePicker _picker = ImagePicker();

  DriverInformationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0, iconTheme: IconThemeData(color: Colors.black)),
      body: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Drivers Information', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            SizedBox(height: 12),
            Text('Driver licence number'),
            SizedBox(height: 6),
            TextField(decoration: _decoration.copyWith(hintText: 'A5678888')),
            SizedBox(height: 12),
            Text('Upload front of driver\'s license*'),
            SizedBox(height: 6),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(border: Border.all(color: Colors.grey[300]!), borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                SizedBox(width: 80, height: 80, child: localImage('/mnt/data/Driver_information.png', fit: BoxFit.cover)),
                SizedBox(width: 12),
                Expanded(child: ElevatedButton(onPressed: ()   async {
                  final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
                  if (image != null) {
                    // handle the selected image file here
                  }
                }, child: Text('Choose File'))),
              ]),
            ),
            SizedBox(height: 12),
            Text('Upload back of driver\'s licence*'),
            SizedBox(height: 6),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(border: Border.all(color: Colors.grey[300]!), borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                SizedBox(width: 80, height: 80, child: localImage('/mnt/data/Driver_information.png', fit: BoxFit.cover)),
                SizedBox(width: 12),
                Expanded(child: ElevatedButton(onPressed: ()   async {
                  final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
                  if (image != null) {
                    // handle the selected image file here
                  }
                }, child: Text('Choose File'))),
              ]),
            ),
            Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => {
                  Navigator.push(context,
                    MaterialPageRoute(builder: (context) => AddPhotoScreen()),
                  )
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.yellow[700], foregroundColor: Colors.black),
                child: Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Text('Next')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
