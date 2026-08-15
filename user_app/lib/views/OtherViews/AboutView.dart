import 'package:flutter/material.dart';

class AboutView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(70),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(24),
              bottomRight: Radius.circular(24),
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: const [
                  BackButton(color: Colors.black),
                  Spacer(),
                  Text(
                    'About Ravel Go',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.normal, color: Colors.black),
                  ),
                  Spacer(),
                  SizedBox(width: 64)
                ],
              ),
            ),
          ),
        ),
      ),
      backgroundColor: Colors.white,
      body: ListView(
        children: [
          ListTile(
            title: Text('Where does Ravel Go operate',style: TextStyle(fontSize: 16, fontWeight: FontWeight.normal, color: Colors.black),),
            trailing: Icon(Icons.arrow_forward_ios),
            onTap: () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Where does Ravel Go operate'),
                  content: const Text('Ravel Go currently operates in major cities across Nigeria. We are expanding to more locations soon.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
                  ],
                ),
              );
            },
          ),
          ListTile(
            title: Text('Where is Ravel Go office located',style: TextStyle(fontSize: 16, fontWeight: FontWeight.normal, color: Colors.black),),
            trailing: Icon(Icons.arrow_forward_ios),
            onTap: () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Where is Ravel Go office located'),
                  content: const Text('For office location and contact details, please reach out to support@ravelgo.com.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}