import 'package:flutter/material.dart';
import 'package:ravelgo_user_app/views/Services/AddBankAccountPage.dart';
import 'IdelivaPickUpDeliveryScreen.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';

class IdelivaProfileScreen extends StatefulWidget {
  const IdelivaProfileScreen({super.key});

  @override
  State<IdelivaProfileScreen> createState() =>
      _IdelivaProfileScreenState();
}

class _IdelivaProfileScreenState extends State<IdelivaProfileScreen> {
  String selectedMode = 'vehicle';
  String selectedMonth = 'September';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,

      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              /// BACK + TITLE
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),

              /// EARN CARD
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 18),
                decoration: BoxDecoration(
                  color: AppColors.textPrimary,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [

                    /// TITLE
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Text(
                          'Total Earns',
                          style: TextStyle(
                              color: AppColors.surface, fontSize: 14),
                        ),
                        SizedBox(width: 6),
                        Icon(Icons.visibility_off,
                            color: AppColors.surface, size: 18),
                      ],
                    ),

                    const SizedBox(height: 6),

                    /// AMOUNT
                    const Text(
                      '₦ 0.00',
                      style: TextStyle(
                        color: AppColors.surface,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),

                    const SizedBox(height: 8),

                    /// DOTS
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        CircleAvatar(radius: 2, backgroundColor: AppColors.surface),
                        SizedBox(width: 4),
                        CircleAvatar(radius: 2, backgroundColor: AppColors.surface),
                        SizedBox(width: 4),
                        CircleAvatar(radius: 2, backgroundColor: AppColors.surface),
                      ],
                    ),

                    const SizedBox(height: 12),

                    /// TEXT
                    const Text(
                      'Provide the bank account for receiving payouts',
                      style: TextStyle(
                          color: AppColors.surface, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 14),

                    /// BUTTON (FULL WIDTH)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const AddBankAccountPage(),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: AppColors.textPrimary,
                          padding:
                          const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          elevation: 0,
                        ),
                        child: const Text(
                          'Add bank account +',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 22),

              /// PICKUP MODE
              const Text(
                'Pick up mode',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),

              const SizedBox(height: 8),

              Row(
                children: [
                  _radio('vehicle', 'Your vehicle'),
                  const SizedBox(width: 20),
                  _radio('foot', 'By foot'),
                ],
              ),

              const SizedBox(height: 14),

              /// PICK ORDER BUTTON
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>  PickDeliveryScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.ads_click),
                  label: const Text('Pick an order'),
                  style: OutlinedButton.styleFrom(
                    padding:
                    const EdgeInsets.symmetric(vertical: 14),
                    side: BorderSide(color: AppColors.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              Divider(color: AppColors.border),

              const SizedBox(height: 12),

              /// HEADER
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [

                  const Text(
                    'Delivery history',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),

                  /// MONTH DROPDOWN CHIP STYLE
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 15, vertical: 0),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.border),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: DropdownButton<String>(
                      value: selectedMonth,
                      underline: const SizedBox(),
                      icon: const Icon(Icons.keyboard_arrow_down, size: 18),
                      items: ['September', 'August', 'July']
                          .map((e) => DropdownMenuItem(
                        value: e,
                        child: Text(e),
                      ))
                          .toList(),
                      onChanged: (value) {
                        setState(() {
                          selectedMonth = value!;
                        });
                      },
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              /// DELIVERY ITEM
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: const [
                  Text('8 Sept, 21:18'),
                  Text(
                    'NGN4000',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              Row(
                children: [
                  Image.asset('assets/ic_pickup.png', width: 22),
                  const SizedBox(width: 8),
                  const Text('Denco court 1'),
                ],
              ),

              const SizedBox(height: 6),

              Row(
                children: [
                  Image.asset('assets/ic_destination.png', width: 22),
                  const SizedBox(width: 8),
                  const Text('Destination'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// CUSTOM RADIO (CLEAN LOOK)
  Widget _radio(String value, String title) {
    return InkWell(
      onTap: () {
        setState(() {
          selectedMode = value;
        });
      },
      child: Row(
        children: [
          Radio<String>(
            value: value,
            groupValue: selectedMode,
            onChanged: (val) {
              setState(() {
                selectedMode = val!;
              });
            },
            activeColor: Colors.deepPurple,
          ),
          Text(title),
        ],
      ),
    );
  }
}