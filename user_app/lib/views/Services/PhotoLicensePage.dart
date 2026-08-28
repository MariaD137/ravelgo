import 'package:flutter/material.dart';
import 'package:ravelgo_user_app/components/basic_components.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';

class PhotoLicensePage extends StatelessWidget {
  const PhotoLicensePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [

            AppComponents.header(context, "Photo with drivers license"),

            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Container(
                  decoration: AppComponents.cardDecoration(),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [

                      Container(
                        width: 180,
                        height: 180,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: AppColors.border,
                        ),
                      ),

                      const SizedBox(height: 20),

                      OutlinedButton(
                        onPressed: () {},
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text("Add a photo"),
                      ),

                      const SizedBox(height: 20),

                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20),
                        child: Text(
                          "Hold your driver’s license next to your face and take a clear photo, ensuring all information is readable.",
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            AppComponents.primaryButton(text: "Done", onPressed: (){
              Navigator.pop(context);
            })
          ],
        ),
      ),
    );
  }
}