import 'package:flutter/material.dart';
import 'package:ravelgo_user_app/services/rider_api.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';

class EditPersonalInfo extends StatefulWidget {
  final String? initialFirstName;
  final String? initialLastName;
  final String? initialPhoneNumber;
  final String? email;

  const EditPersonalInfo({
    super.key,
    this.initialFirstName,
    this.initialLastName,
    this.initialPhoneNumber,
    this.email,
  });

  @override
  State<EditPersonalInfo> createState() => _EditPersonalInfoState();
}

class _EditPersonalInfoState extends State<EditPersonalInfo> {
  late final TextEditingController _firstNameController =
      TextEditingController(text: widget.initialFirstName ?? '');
  late final TextEditingController _lastNameController =
      TextEditingController(text: widget.initialLastName ?? '');
  late final TextEditingController _phoneController =
      TextEditingController(text: widget.initialPhoneNumber ?? '');

  bool _saving = false;

  Future<void> _save() async {
    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    final phone = _phoneController.text.trim();
    if (firstName.isEmpty || lastName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('First and last name are required.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await RiderApi.updateMe(
        firstName: firstName,
        lastName: lastName,
        phoneNumber: phone.isEmpty ? null : phone,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(color: AppColors.textPrimary),
        backgroundColor: AppColors.surface,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          "Edit Personal Info",
          style: TextStyle(color: AppColors.textPrimary),
        ),
      ),
      body: Container(
        color: AppColors.surface,
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
            const SizedBox(height: 20),
            _buildLabel("Email address"),
            TextFormField(
              enabled: false,
              initialValue: widget.email ?? '',
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.email_outlined),
                helperText: 'Email is tied to your sign-in and can\'t be changed here.',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: _saving
                    ? const SizedBox(
                        height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Save', style: TextStyle(color: Colors.white, fontSize: 16)),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required IconData icon,
    TextInputType? keyboardType,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        prefixIcon: Icon(icon),
        suffixIcon: IconButton(
          icon: const Icon(Icons.clear),
          onPressed: () => controller.clear(),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}

class _ProfilePhotoSection extends StatelessWidget {
  const _ProfilePhotoSection();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
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
                backgroundColor: AppColors.textMuted,
                child: Icon(Icons.person, size: 40, color: AppColors.surface),
              ),
              Positioned(
                right: 0,
                child: CircleAvatar(
                  radius: 12,
                  backgroundColor: AppColors.surface,
                  child: Icon(Icons.edit, size: 14, color: AppColors.textPrimary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            "Upload a profile photo",
            style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
          ),
          const Text(
            "to help drivers identify you easily",
            style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
