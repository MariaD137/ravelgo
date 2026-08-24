import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dotted_border/dotted_border.dart';

class InviteFriendsView extends StatelessWidget {
  const InviteFriendsView({super.key});

  final String referralCode = "HKPY8HGC5DET2";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F4F4),
      body: Stack(
        children: [

          /// 🔹 BLACK HEADER
          ///

        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child:Container(
            height: 200,
            width: double.infinity,
            color: Colors.black,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child:Column(
                  children: [
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: const CircleAvatar(
                              radius: 20,
                              backgroundColor: Colors.white,
                              child: Icon(Icons.arrow_back, color: Colors.black),
                            ),
                          ),
                        ),
                        const Text(
                          "Invite Friends",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 80,),
                  ],
                ),

              ),
            ),
          ),
        ),

          /// 🔹 WHITE CARD CONTENT
          Positioned(
            top: 140,
            left: 20,
            right: 20,

            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(1, 6),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    "Refer Friends",
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    "Invite a new driver and get 5%\n"
                        "discount on your next subscription!",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 40),

                   Image.asset('assets/invite_a_refer.png',width: 110,height: 110,fit: BoxFit.fill,),
                  // const Icon(
                  //   Icons.groups_rounded,
                  //   size: 110,
                  //   color: Color(0xFF7A6A00),
                  // ),

                  const SizedBox(height: 40),

                  const Text(
                    "Your code invite",
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: Colors.black54,
                    ),
                  ),

                  const SizedBox(height: 30),

                    DottedBorder(
                      options: RectDottedBorderOptions(
                        dashPattern: [4, 5],
                        strokeWidth: 1,
                        color: Colors.blueAccent,
                        padding: EdgeInsets.all(16),
                      ),
                      child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 2),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        color: Colors.white,
                      ),
                      child: Row(
                        mainAxisAlignment:
                        MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            referralCode,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          GestureDetector(
                            onTap: () {
                              Clipboard.setData(ClipboardData(text: referralCode));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Referral code copied to clipboard')),
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFD700),
                                borderRadius:
                                BorderRadius.circular(8),
                              ),
                              child: const Text(
                                "Copy",
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black,
                                ),
                              ),
                            ),
                          )
                        ],
                      ),
                    ),
                    ),
                  // DottedBorder(
                  //   borderType: BorderType.RRect,
                  //   radius: const Radius.circular(16),
                  //   dashPattern: const [4, 4],
                  //   color: Colors.blueAccent,
                  //   strokeWidth: 1.5,
                  //   child: Container(
                  //     padding: const EdgeInsets.symmetric(
                  //         horizontal: 16, vertical: 2),
                  //     decoration: BoxDecoration(
                  //       borderRadius: BorderRadius.circular(16),
                  //       color: Colors.white,
                  //     ),
                  //     child: Row(
                  //       mainAxisAlignment:
                  //       MainAxisAlignment.spaceBetween,
                  //       children: [
                  //         Text(
                  //           referralCode,
                  //           style: const TextStyle(
                  //             fontSize: 16,
                  //             fontWeight: FontWeight.w600,
                  //           ),
                  //         ),
                  //         Container(
                  //           padding: const EdgeInsets.symmetric(
                  //               horizontal: 16, vertical: 8),
                  //           decoration: BoxDecoration(
                  //             color: const Color(0xFFFFD700),
                  //             borderRadius:
                  //             BorderRadius.circular(8),
                  //           ),
                  //           child: const Text(
                  //             "Copy",
                  //             style: TextStyle(
                  //               fontWeight: FontWeight.w600,
                  //               color: Colors.black,
                  //             ),
                  //           ),
                  //         )
                  //       ],
                  //     ),
                  //   ),
                  // ),

                  const SizedBox(height: 15),
                ],
              ),
            ),
          ),
        ],
      ),

      /// 🔹 SHARE BUTTON
      bottomNavigationBar: Padding(
        padding:
        const EdgeInsets.fromLTRB(20, 0, 20, 25),
        child: SizedBox(
          height: 55,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor:
              const Color(0xFFFFD700),
              shape: RoundedRectangleBorder(
                borderRadius:
                BorderRadius.circular(14),
              ),
            ),
            onPressed: () {},
            icon: const Icon(Icons.share,
                color: Colors.black),
            label: const Text(
              "Share",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.black,
              ),
            ),
          ),
        ),
      ),
    );
  }
}