import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../design/pp.dart';

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          "Privacy & Security",
          style: GoogleFonts.poppins(
            color: Colors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF8E2DE2).withOpacity(0.1),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.shield_outlined,
                    color: Color(0xFF8E2DE2),
                    size: 30,
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Text(
                      "Your data is encrypted and secure.",
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF8E2DE2),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),
            Text(
              "Privacy Policy",
              style: GoogleFonts.poppins(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 15),
            Text(
              "At PurePick, your health and privacy are our top priorities. Your personal allergy profile and scan history are stored securely within your account. We use this data explicitly for the purpose of analyzing product ingredients against your specific conditions via our AI pipeline. We do not sell your personal data to third parties.",
              style: GoogleFonts.poppins(
                fontSize: 15,
                height: 1.6,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 25),
            Text(
              "Data Security",
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              "We utilize industry-standard encryption practices to secure your profile. Images uploaded for scanning are processed seamlessly by our backend OCR engines and are not permanently retained on our servers after analysis is completed.",
              style: GoogleFonts.poppins(
                fontSize: 15,
                height: 1.6,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 40),
            Center(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 40,
                    vertical: 15,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: Text(
                  "Acknowledge & Return",
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
