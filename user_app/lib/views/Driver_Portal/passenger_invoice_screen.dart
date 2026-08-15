import 'package:flutter/material.dart';
import 'package:ravelgo_user/views/Driver_Portal/side_menu_driver.dart';

class PassengerInvoiceScreen extends StatelessWidget {
  const PassengerInvoiceScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const SideMenuDriver(initialSelectedItem: "Passenger Invoices",),
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              /// HEADER
              Row(
                children: [
                  Builder(
                    builder: (context) => GestureDetector(
                      onTap: () => Scaffold.of(context).openDrawer(),
                      child: Container(
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(color: Colors.black12, blurRadius: 6),
                          ],
                        ),
                        child: const CircleAvatar(
                          backgroundColor: Colors.white,
                          child: Icon(Icons.menu, color: Colors.black),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Image.asset(
                    "assets/ravel_go_driver_badge.png",
                    height: 28,
                  ),
                ],
              ),

              const SizedBox(height: 28),

              const Text(
                "Invoices",
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
              ),

              const SizedBox(height: 20),

              /// FILTERS
              Row(
                children: [
                  Expanded(child: _filterBox("April 2025")),
                  const SizedBox(width: 14),
                  Expanded(child: _filterBox("Payment method")),
                ],
              ),

              const SizedBox(height: 14),

              OutlinedButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Feature coming soon')),
                  );
                },
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text("Download"),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),

              const SizedBox(height: 24),

              /// SCROLLABLE TABLE
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: 750, // fixed table width
                    child: Column(
                      children: [

                        /// TABLE HEADER
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          color: Colors.grey.shade300,
                          child: Row(
                            children: const [
                              _HeaderCell("Date", 100),
                              _HeaderCell("Pick-Up Address", 200),
                              _HeaderCell("Sum", 100),
                              _HeaderCell("Payment method", 200),
                              _HeaderCell("PDF", 100),
                            ],
                          ),
                        ),

                        /// TABLE BODY
                        Expanded(
                          child: ListView.builder(
                            itemCount: 20,
                            itemBuilder: (context, index) {
                              return Container(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                decoration: BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(
                                        color: Colors.grey.shade300),
                                  ),
                                ),
                                child: Row(
                                  children: const [
                                    _DataCell("10/22/23", 100),
                                    _DataCell("Denco court", 200),
                                    _DataCell("#5000", 100),
                                    _DataCell("Transfer", 200),
                                    _DataCell("PDF", 100),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filterBox(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(child: Text(text)),
          const Icon(Icons.keyboard_arrow_down),
        ],
      ),
    );
  }
}

/// HEADER CELL
class _HeaderCell extends StatelessWidget {
  final String text;
  final double width;

  const _HeaderCell(this.text, this.width, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Text(
        text,
        style:
        const TextStyle(fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// DATA CELL
class _DataCell extends StatelessWidget {
  final String text;
  final double width;

  const _DataCell(this.text, this.width, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Text(text),
    );
  }
}