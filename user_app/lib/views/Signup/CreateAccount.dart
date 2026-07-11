import 'dart:io';
import 'package:flutter/material.dart';
import 'package:ravelgo_driver/views/Signup/VerifyAccount.dart';

class CreateAccountScreen extends StatelessWidget {
  final _fieldDecoration = InputDecoration(
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6.0)),
    contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 18),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: 6),
              IconButton(icon: Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              SizedBox(height: 6),
              Text('Become a driver', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('Fill your information below and become a driver', style: TextStyle(color: Colors.grey[600])),
              SizedBox(height: 18),
              Text('Email'),
              SizedBox(height: 6),
              TextField(decoration: _fieldDecoration.copyWith(hintText: 'Enter Email')),
              SizedBox(height: 12),
              Text('Phone Number'),
              SizedBox(height: 6),
              TextField(decoration: _fieldDecoration.copyWith(hintText: 'Enter Phone number')),
              SizedBox(height: 12),
              Text('City'),
              SizedBox(height: 6),
              DropdownButtonFormField<String>(items: [DropdownMenuItem(child: Text('Enter City'), value: 'Enter City'),DropdownMenuItem(child: Text('Ahmedabad'), value: 'Ahmedabad')], onChanged: (_) {}, decoration: _fieldDecoration),
              SizedBox(height: 12),
              Row(children: [
                Checkbox(value: true, onChanged: (_) {}),
                Expanded(child: Text('Agree with Terms & Condition'))
              ]),
              SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: ()=>{
                    Navigator.push(context,
                      MaterialPageRoute(builder: (context) => VerifyAccountScreen()),
                    )
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.yellow[700], foregroundColor: Colors.black, disabledBackgroundColor: Colors.yellow[100]),
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('Register as a driver', style: TextStyle(fontSize: 16)),
                  ),
                ),
              ),
              SizedBox(height: 18),
              Center(child: Text('Already have an account? Sign in', style: TextStyle(color: Colors.blue))),
            ],
          ),
        ),
      ),
    );
  }
}