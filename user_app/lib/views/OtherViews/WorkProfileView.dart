import 'package:flutter/material.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';

/// Rider business/work profile settings.
/// LOCAL STATE ONLY: edits update in-memory values for this session; syncing
/// them is the integration point for the profile backend.
class WorkProfileView extends StatefulWidget {
  const WorkProfileView({super.key});

  @override
  State<WorkProfileView> createState() => _WorkProfileViewState();
}

class _WorkProfileViewState extends State<WorkProfileView> {
  String? _companyName;
  String _workEmail = 'thelmaibeh2@gmail.com';
  String _paymentMethod = 'Cash';

  Future<void> _editText({
    required String title,
    required String? current,
    required ValueChanged<String> onSaved,
    TextInputType keyboardType = TextInputType.text,
  }) async {
    final controller = TextEditingController(text: current ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: keyboardType,
          decoration: const InputDecoration(hintText: 'Enter value'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      onSaved(result);
      setState(() {});
    }
  }

  Future<void> _pickPaymentMethod() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Work payment method',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
            for (final m in const ['Cash', 'Card', 'Company billing'])
              ListTile(
                title: Text(m),
                trailing: m == _paymentMethod ? const Icon(Icons.check, color: AppColors.success) : null,
                onTap: () => Navigator.pop(context, m),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (result != null) setState(() => _paymentMethod = result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        leading: const BackButton(color: AppColors.textPrimary),
        backgroundColor: AppColors.surface,
        elevation: 0,
        centerTitle: true,
        title: const Text('Work Profile',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.normal, color: AppColors.textPrimary)),
      ),
      body: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: ListView(
          children: [
            _SettingsTile(
              icon: Icons.work_outline,
              title: _companyName == null ? 'Add company details' : 'Company',
              value: _companyName,
              showValue: _companyName != null,
              onTap: () => _editText(
                title: 'Company name',
                current: _companyName,
                onSaved: (v) => _companyName = v,
              ),
            ),
            const Divider(height: 1),
            _SettingsTile(
              icon: Icons.email_outlined,
              title: 'Work email',
              value: _workEmail,
              onTap: () => _editText(
                title: 'Work email',
                current: _workEmail,
                keyboardType: TextInputType.emailAddress,
                onSaved: (v) => _workEmail = v,
              ),
            ),
            const Divider(height: 1),
            _SettingsTile(
              icon: Icons.account_balance_wallet_outlined,
              title: 'Payment method',
              value: _paymentMethod,
              onTap: _pickPaymentMethod,
            ),
            const Divider(height: 1),
          ],
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? value;
  final bool showValue;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    this.value,
    this.showValue = true,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Icon(icon, color: AppColors.textSecondary),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: (showValue && value != null)
            ? [
                Text(title, style: const TextStyle(color: AppColors.textMuted, fontSize: 14)),
                Text(
                  value!,
                  style: const TextStyle(
                      color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w500),
                ),
              ]
            : [
                Text(
                  title,
                  style: const TextStyle(
                      color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w500),
                ),
              ],
      ),
      trailing: const Icon(Icons.chevron_right, color: AppColors.textMuted),
      onTap: onTap,
    );
  }
}
