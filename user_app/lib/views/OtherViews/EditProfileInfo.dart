import 'package:flutter/material.dart';
import 'package:ravelgo_rider_app/services/api/api_client.dart';
import 'package:ravelgo_rider_app/services/api/rider_api.dart';

/// Edits the rider's own name/phone via PATCH /api/riders/me. Email is
/// shown read-only — it's tied to the Cognito identity the profile was
/// bootstrapped from, and the backend deliberately doesn't accept it here
/// (see riders.routes.ts). The previous version of this screen had no
/// Save button at all — every field was decorative, pre-filled with a
/// fixed sample name/phone/email that no tap could ever change.
class EditPersonalInfo extends StatefulWidget {
  const EditPersonalInfo({
    super.key,
    required this.firstName,
    required this.lastName,
    required this.phoneNumber,
    this.email,
    this.riderApi,
  });

  final String firstName;
  final String lastName;
  final String phoneNumber;
  final String? email;
  final RiderApi? riderApi;

  @override
  State<EditPersonalInfo> createState() => _EditPersonalInfoState();
}

class _EditPersonalInfoState extends State<EditPersonalInfo> {
  late final RiderApi _api = widget.riderApi ?? RiderApi(ApiClient());
  late final TextEditingController _firstNameController = TextEditingController(text: widget.firstName);
  late final TextEditingController _lastNameController = TextEditingController(text: widget.lastName);
  late final TextEditingController _phoneController = TextEditingController(text: widget.phoneNumber);
  bool _saving = false;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_firstNameController.text.trim().isEmpty || _lastNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('First and last name are required.')));
      return;
    }
    setState(() => _saving = true);
    try {
      await _api.updateMe(
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        phoneNumber: _phoneController.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save: $err')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(color: Colors.black),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text("Edit Personal Info", style: TextStyle(color: Colors.black)),
      ),
      body: Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: ListView(
          children: [
            const _ProfilePhotoSection(),
            const SizedBox(height: 30),
            _buildLabel("First Name"),
            _buildTextField(controller: _firstNameController, icon: Icons.person_outline),
            const SizedBox(height: 20),
            _buildLabel("Last Name"),
            _buildTextField(controller: _lastNameController, icon: Icons.person_outline),
            const SizedBox(height: 20),
            _buildLabel("Phone Number"),
            _buildTextField(controller: _phoneController, icon: Icons.phone_outlined, keyboardType: TextInputType.phone),
            if (widget.email != null) ...[
              const SizedBox(height: 20),
              _buildLabel("Email address"),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                decoration: BoxDecoration(border: Border.all(color: Colors.black12), borderRadius: BorderRadius.circular(8)),
                child: Row(
                  children: [
                    const Icon(Icons.lock_outline, size: 18, color: Colors.black45),
                    const SizedBox(width: 10),
                    Expanded(child: Text(widget.email!)),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Save'),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
    );
  }

  Widget _buildTextField({required TextEditingController controller, required IconData icon, TextInputType? keyboardType}) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        prefixIcon: Icon(icon),
        suffixIcon: IconButton(icon: const Icon(Icons.clear), onPressed: () => controller.clear()),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}

class _ProfilePhotoSection extends StatelessWidget {
  const _ProfilePhotoSection();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF8F8F8),
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
          const Text("Upload a profile photo", style: TextStyle(fontSize: 14, color: Colors.black54)),
          const Text("to help drivers identify you easily", style: TextStyle(fontSize: 14, color: Colors.black54)),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
