import 'package:flutter/material.dart';
import 'package:ravelgo_user/services/api_client.dart';
import 'package:ravelgo_user/views/OtherViews/EditProfileInfo.dart';

class PersonalInfo extends StatefulWidget {
  const PersonalInfo({super.key});

  @override
  State<PersonalInfo> createState() => _PersonalInfoState();
}

class _PersonalInfoState extends State<PersonalInfo> {
  String _fullName = '';
  String _phone = '';
  String _email = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final data = await ApiClient().get('/riders/me');
      if (!mounted) return;
      setState(() {
        final firstName = data['firstName'] ?? '';
        final lastName = data['lastName'] ?? '';
        _fullName = '$firstName $lastName'.trim();
        _phone = data['phoneNumber'] ?? '';
        _email = data['email'] ?? '';
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(color: Colors.black),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          "Personal Info",
          style: TextStyle(color: Colors.black),
        ),
      ),
      body: Container(
    color: Colors.white,
    child: Column(
        children: [

          _ProfileSection(),
          const SizedBox(height: 30),
          InfoTile(
            icon: Icons.person_outline,
            text: _fullName.isNotEmpty ? _fullName : 'Not set',
          ),
          InfoTile(
            icon: Icons.phone_outlined,
            text: _phone.isNotEmpty ? _phone : 'Not set',
          ),
          InfoTile(
            icon: Icons.email_outlined,
            text: _email.isNotEmpty ? _email : 'Not set',
          ),
          const InfoTile(
            icon: Icons.lock_outline,
            text: '********',
          ),
        ],
      ),
      ),
    );
  }
}

class _ProfileSection extends StatelessWidget {
  const _ProfileSection();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Color(0xFFF8F8F8),
      height: 180,
      width: double.infinity,
      child: Column(
      children: [
        const SizedBox(height: 20),
        Stack(
          alignment: Alignment.bottomRight,
          children: [
            const CircleAvatar(
              radius: 40,
              backgroundColor: Colors.grey,
              child: Icon(Icons.person, size: 40, color: Colors.white),
            ),
            Positioned(
              right: 0,
              child: CircleAvatar(
                radius: 12,
                backgroundColor: Colors.white,
                child: Icon(Icons.edit, size: 14, color: Colors.black),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Text(
          "Upload a profile photo",
          style: TextStyle(fontSize: 14, color: Colors.black54),
        ),
        const Text(
          "to help drivers identify you easily",
          style: TextStyle(fontSize: 14, color: Colors.black54),
        ),
        const SizedBox(height: 20),
      ],
    ),);
  }
}

class InfoTile extends StatelessWidget {
  final IconData icon;
  final String text;

  const InfoTile({
    super.key,
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.black26),
          borderRadius: BorderRadius.circular(8),
        ),
        child: ListTile(
          leading: Icon(icon, color: Colors.black54),
          title: Text(text),
          trailing: const Icon(Icons.edit_outlined, color: Colors.black54),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => EditPersonalInfo()),
            );
          },
        ),
      ),
    );
  }
}
