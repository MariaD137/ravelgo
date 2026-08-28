import 'package:flutter/material.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';


class EditPersonalInfo extends StatefulWidget {
  const EditPersonalInfo({super.key});

  @override
  State<EditPersonalInfo> createState() => _EditPersonalInfoState();
}

class _EditPersonalInfoState extends State<EditPersonalInfo> {
  final TextEditingController _firstNameController = TextEditingController(text: 'Thelma');
  final TextEditingController _lastNameController = TextEditingController(text: 'Ibeh');
  final TextEditingController _phoneController = TextEditingController(text: '+2348130006677');
  final TextEditingController _emailController = TextEditingController(text: 'user@gmail.com');

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
            _buildTextField(controller: _emailController, icon: Icons.email_outlined, keyboardType: TextInputType.emailAddress),
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
      width: double.infinity,// 👈 Set background color here
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
      ),);
  }
}