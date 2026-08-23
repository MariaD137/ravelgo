import 'package:flutter/material.dart';
import 'package:ravelgo_rider_app/services/api/api_client.dart';
import 'package:ravelgo_rider_app/services/api/rider_api.dart';
import 'package:ravelgo_rider_app/views/OtherViews/EditProfileInfo.dart';

/// The rider's own profile — GET /api/riders/me on the backend. Previously
/// every field here (name, phone, email, and a "password" field with no
/// backend equivalent at all — passwords are Cognito's concern, never
/// stored in Postgres) was a hardcoded sample; that fake password tile has
/// been removed entirely rather than replaced with something misleading.
class PersonalInfo extends StatefulWidget {
  PersonalInfo({super.key, RiderApi? riderApi}) : riderApi = riderApi ?? RiderApi(ApiClient());

  final RiderApi riderApi;

  @override
  State<PersonalInfo> createState() => _PersonalInfoState();
}

class _PersonalInfoState extends State<PersonalInfo> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.riderApi.getMe();
  }

  Future<void> _refresh() async {
    final future = widget.riderApi.getMe();
    setState(() => _future = future);
    await future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(color: Colors.black),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text("Personal Info", style: TextStyle(color: Colors.black)),
      ),
      body: Container(
        color: Colors.white,
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: FutureBuilder<Map<String, dynamic>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    const SizedBox(height: 80),
                    Center(child: Text('Failed to load: ${snapshot.error}', textAlign: TextAlign.center)),
                    const SizedBox(height: 12),
                    Center(child: TextButton(onPressed: _refresh, child: const Text('Retry'))),
                  ],
                );
              }
              final rider = snapshot.data!;
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const _ProfileSection(),
                  const SizedBox(height: 30),
                  InfoTile(
                    icon: Icons.person_outline,
                    text: '${rider['firstName']} ${rider['lastName']}',
                    onEdit: () => _editAndRefresh(rider),
                  ),
                  InfoTile(
                    icon: Icons.phone_outlined,
                    text: (rider['phoneNumber'] as String?)?.isNotEmpty == true
                        ? rider['phoneNumber'] as String
                        : 'Not set',
                    onEdit: () => _editAndRefresh(rider),
                  ),
                  InfoTile(icon: Icons.email_outlined, text: rider['email'] as String? ?? '—'),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _editAndRefresh(Map<String, dynamic> rider) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => EditPersonalInfo(
          riderApi: widget.riderApi,
          firstName: rider['firstName'] as String? ?? '',
          lastName: rider['lastName'] as String? ?? '',
          phoneNumber: rider['phoneNumber'] as String? ?? '',
          email: rider['email'] as String?,
        ),
      ),
    );
    if (changed == true) await _refresh();
  }
}

class _ProfileSection extends StatelessWidget {
  const _ProfileSection();

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

class InfoTile extends StatelessWidget {
  final IconData icon;
  final String text;
  final VoidCallback? onEdit;

  const InfoTile({super.key, required this.icon, required this.text, this.onEdit});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Container(
        decoration: BoxDecoration(border: Border.all(color: Colors.black26), borderRadius: BorderRadius.circular(8)),
        child: ListTile(
          leading: Icon(icon, color: Colors.black54),
          title: Text(text),
          trailing: onEdit != null ? const Icon(Icons.edit_outlined, color: Colors.black54) : null,
          onTap: onEdit,
        ),
      ),
    );
  }
}
