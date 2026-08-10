import 'package:flutter/material.dart';

class NameField extends StatelessWidget {
  static const Color primary = Color(0xFF6D4C41);

  final TextEditingController controller;
  final bool isWaiting;

  const NameField({
    super.key,
    required this.controller,
    required this.isWaiting,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: TextField(
        controller: controller,
        enabled: !isWaiting,
        decoration: InputDecoration(
          labelText: "Your Name",
          prefixIcon: const Icon(Icons.person_outline, color: primary),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.brown.shade100),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: primary, width: 1.5),
          ),
        ),
      ),
    );
  }
}