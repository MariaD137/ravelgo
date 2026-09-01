import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';

class RideViewPopup extends StatefulWidget {
  final VoidCallback onClose;

  const RideViewPopup({Key? key, required this.onClose}) : super(key: key);

  @override
  State<RideViewPopup> createState() => _RideViewPopupState();
}

class _RideViewPopupState extends State<RideViewPopup> {
  int stage = 1;
  Timer? timer;

  @override
  void initState() {
    super.initState();

    timer = Timer.periodic(const Duration(seconds: 30), (t) {
      if (stage < 4) {
        setState(() => stage++);
      } else {
        t.cancel();
      }
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [

          Expanded(
            child: stage == 4
                ? _stageFour()
                : SingleChildScrollView(
              padding: const EdgeInsets.all(0),
              child: Column(
                children: [
                  _topBar(),
                  _statusTitle(),
                  const SizedBox(height: 16),
                  _profileSection(),
                  const SizedBox(height: 16),
                  _routeCard(),
                  const SizedBox(height: 16),
                  _moreCard(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ================= TOP YELLOW =================

  Widget _topBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(top: 12, bottom: 18),
      decoration: const BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          Container(
            width: 48,
            height: 5,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: AppColors.textSecondary,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.shield_outlined, size: 16),
                SizedBox(width: 6),
                Text("Safety",
                    style: TextStyle(
                        fontWeight: FontWeight.w600)),
              ],
            ),
          )
        ],
      ),
    );
  }

  // ================= STATUS TITLE =================

  Widget _statusTitle() {
    String text = "";
    if (stage == 1) text = "Driving to pick-up";
    if (stage == 2) text = "You have arrived!";
    if (stage == 3) text = "Driving to your destination";

    return Text(
      text,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: AppColors.primaryDark,
      ),
    );
  }

  // ================= PROFILE =================

  Widget _profileSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const CircleAvatar(
                radius: 22,
                backgroundImage: NetworkImage(
                    "https://i.pravatar.cc/150?img=47"),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment:
                CrossAxisAlignment.start,
                children: const [
                  Text("Thelma Ibeh",
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15)),
                  SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.star,
                          size: 16, color: Colors.green),
                      SizedBox(width: 4),
                      Text("4.55 Rating",
                          style:
                          TextStyle(fontSize: 13)),
                    ],
                  )
                ],
              )
            ],
          ),
          const Divider(height: 28),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding:
                  const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius:
                    BorderRadius.circular(12),
                  ),
                  child:
                  const Text("Any pickup notes?"),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius:
                  BorderRadius.circular(12),
                ),
                child:
                const Icon(Icons.call, size: 18),
              )
            ],
          )
        ],
      ),
    );
  }

  // ================= ROUTE CARD =================

  Widget _routeCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: const [
          Text("My route",
              style: TextStyle(
                  fontWeight: FontWeight.w600)),
          SizedBox(height: 12),
          Text("Denco court 1"),
          SizedBox(height: 6),
          Text("skybox"),
        ],
      ),
    );
  }

  // ================= MORE CARD =================

  Widget _moreCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: const [
          Text("More",
              style: TextStyle(
                  fontWeight: FontWeight.w600)),
          SizedBox(height: 16),
          Row(
            mainAxisAlignment:
            MainAxisAlignment.spaceBetween,
            children: [
              Icon(Icons.share),
              SizedBox(width: 4,),
              Text("Share trip details"),
              Spacer(),
              Icon(Icons.chevron_right),
            ],
          ),
          SizedBox(height: 12),
          Row(
            mainAxisAlignment:
            MainAxisAlignment.spaceBetween,
            children: [
              Icon(Icons.phone),
              SizedBox(width: 4,),
              Text("Contact rider"),
              Spacer(),
              Icon(Icons.chevron_right),
            ],
          ),
        ],
      ),
    );
  }

  // ================= STAGE 4 =================

  Widget _stageFour() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment:
        MainAxisAlignment.spaceBetween,
        children: [
          const SizedBox(),
          Column(
            children: const [
              Text("Driving to your destination",
                  style: TextStyle(
                      color: AppColors.primaryDark,
                      fontWeight: FontWeight.w600)),
              SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text("7 min",
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600)),
              ),
              SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: Text("Ozumba mbadiwe"),
              )
            ],
          ),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor:
                AppColors.success,
              ),
              onPressed: () {
                widget.onClose();
              },
              child: const Text("END RIDE"),
            ),
          )
        ],
      ),
    );
  }
}