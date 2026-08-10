import 'package:flutter/material.dart';

class WelcomeText extends StatelessWidget {
  static const Color primary = Color(0xFF6D4C41);
  static const Color primaryDark = Color(0xFF3E2723);

  final String username;

  const WelcomeText({super.key, required this.username});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            const Icon(Icons.person, size: 18, color: primary),
            const SizedBox(width: 6),
            Text(
              "Playing as $username",
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: primaryDark,
              ),
            ),
          ],
        ),
      ),
    );
  }
}