import 'package:flutter/material.dart';
import 'ChoosePlanScreen.dart';

class CarListing extends StatefulWidget {
  const CarListing({Key? key}) : super(key: key);

  @override
  State<CarListing> createState() => _CarListingState();
}

class _CarListingState extends State<CarListing> {
  bool showMore = false;

  final List<Map<String, String>> carList = [
    {
      'image': 'assets/car1.png',
      'name': 'Mercedes Benz (2021)',
    },
    {
      'image': 'assets/car2.png',
      'name': 'BMW X5 (2020)',
    },
    {
      'image': 'assets/car3.png',
      'name': 'Audi A4 (2019)',
    },
    {
      'image': 'assets/car4.png',
      'name': 'Toyota Camry (2022)',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F9F9),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: true, // 👈 Hides the back button
        title: const TextField(
          decoration: InputDecoration(
            hintText: 'Search for a car',
            prefixIcon: Icon(Icons.search),
            border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12)),  borderSide: BorderSide(color: Color(0xFFECECEC)),),
            filled: true,
            fillColor: Color(0xFFECECEC),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Membership Banner
            Container(
              height: 200,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Image.asset(
                    'assets/person_banner.png', // Replace with actual image path
                    width: 150,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Spacer(),
                        const Text(
                          'You can also post your car for rent on our platform',
                          style: TextStyle(color: Colors.white,fontSize: 16,fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 10),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.yellow,
                          ),
                          onPressed: () {},
                          child: const Text('Subscribe to be a Member',style:TextStyle(color: Colors.black,fontSize: 12),),
                        ),
                        Spacer(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Cars available section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Cars available', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      showMore = !showMore;
                    });
                  },
                  child: Text(
                    showMore ? 'See less' : 'See more',
                    style: const TextStyle(color: Colors.green),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Car Listings
            GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              shrinkWrap: true,
              itemCount: showMore ? carList.length : 1,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: showMore ? 2 : 1, // Only one per row
                mainAxisExtent: showMore ? 210 : 390,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.7,
              ),
              itemBuilder: (context, index) {
                final car = carList[index];
                return showMore ? CarCard(
                  name: car['name']!,
                  image: car['image']!,
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const ChoosePlanScreen()));
                  },
                ) : CarCardBig(
                  name: car['name']!,
                  image: car['image']!,
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const ChoosePlanScreen()));
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class CarCard extends StatelessWidget {
  final String name;
  final String image;
  final VoidCallback onTap;

  const CarCard({
    Key? key,
    required this.name,
    required this.image,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.green, width: 1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Image.asset(image, height: 80),
              const SizedBox(height: 10),
              Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text(
                'Automatic | 5 seats | Disel',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 80,
                    height: 32,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.yellow,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size.fromHeight(32),
                      ),
                      icon: const Icon(Icons.call, size: 16, color: Colors.black),
                      label: const Text('Call', style: TextStyle(color: Colors.black, fontSize: 12)),
                      onPressed: () {},
                    ),
                  ),
                  IconButton(
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    icon: Image.asset('assets/ic_whatsapp.png', width: 28),
                    onPressed: () {},
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }
}

class CarCardBig extends StatelessWidget {
  final String name;
  final String image;
  final VoidCallback onTap;

  const CarCardBig({
    Key? key,
    required this.name,
    required this.image,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.green, width: 1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Image.asset(
                image,
                fit: BoxFit.contain,
                width: double.infinity,
              ),
              const SizedBox(height: 10),
              Text(
                name,
                textAlign: TextAlign.left,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 32),
              ),
              const SizedBox(height: 8),
              const Text(
                'Automatic | 5 seats | Disel',
                style: TextStyle(color: Colors.grey, fontSize: 24),
              ),
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.yellow,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    icon: const Icon(Icons.call, size: 18, color: Colors.black),
                    label: const Text('Call', style: TextStyle(color: Colors.black)),
                    onPressed: () {},
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                    icon: Image.asset('assets/ic_whatsapp.png', width: 40),
                    onPressed: () {},
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}