import 'package:flutter/material.dart';

class PaymentView extends StatefulWidget {
  @override
  _PaymentScreenState createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentView> {
  bool isCashSelected = true;
  int selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFF8F8F8),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(70),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(24),
              bottomRight: Radius.circular(24),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: const [
                  BackButton(color: Colors.black),
                  Spacer(),
                  Text(
                    'Payment',
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
      body: Padding(
        padding: const EdgeInsets.all(0.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
              const SizedBox(height: 12),
              Container(
              padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(25),
              ),
              child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Trip profile", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(25),
                            border: Border.all(color: Colors.grey.shade400),
                          ),
                          child: Row(
                            children: [
                              _buildOption("Personal", 0, isSelected: selectedIndex == 0),
                              _buildOption("Work", 1, isSelected: selectedIndex == 1),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
             ),
              const SizedBox(height: 12),
              Container(
                  padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(25),
              ),
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Payment methods', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      ListTile(
                        leading: Image.asset('assets/ic_cash.png'),
                        title: Text('Cash'),
                        trailing: Checkbox(
                          activeColor:Colors.yellow,
                          value: isCashSelected,
                          onChanged: (bool? value) {
                            setState(() {
                              isCashSelected = value!;
                            });
                          },
                        ),
                      ),
                      ListTile(
                        leading: Image.asset('assets/ic_transfer.png'),
                        title: Text('Transfer'),
                        trailing: Checkbox(
                          activeColor:Colors.yellow,
                          value: !isCashSelected,
                          onChanged: (bool? value) {
                            setState(() {
                              isCashSelected = !value!;
                                  });
                                },
                              ),
                            ),
                         ],
                        ),
                      ),
                    ),
                SizedBox(height: 20),
                Container(
                      padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(25),
                      ),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                              GestureDetector(
                                  child:ListTile(
                                            title: Text('Communication preferences',style: TextStyle(fontSize: 18, fontWeight: FontWeight.normal)),
                                            trailing: Image.asset('assets/ic_arrow_right.png')
                                        ),
                                 onTap: () {

                                  },
                                ),
                              ],
                        ),
                      ),
                ),
                SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          GestureDetector(
                            child:ListTile(
                                leading:Image.asset('assets/ic_manage_work_profile.png'),
                                title: Text('Manage work profile',style: TextStyle(fontSize: 18, fontWeight: FontWeight.normal)),
                                trailing: Image.asset('assets/ic_arrow_right.png')
                            ),
                            onTap: () {

                            },
                          ),
                        ],
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
  Expanded _buildOption(String label, int index, {required bool isSelected}) {
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            selectedIndex = index;
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: isSelected ? Colors.amber : Colors.transparent,
            borderRadius: BorderRadius.horizontal(
              left: index == 0 ? const Radius.circular(30) : Radius.zero,
              right: index == 1 ? const Radius.circular(30) : Radius.zero,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: isSelected ? Colors.black : Colors.grey.shade600,
              ),
            ),
          ),
        ),
      ),
    );
  }

}