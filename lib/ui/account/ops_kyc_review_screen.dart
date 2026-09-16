import 'package:flutter/material.dart';
import 'package:hyperlocal/ui/admin/admin_dashboard_screen.dart';

/// Legacy route alias — use [AdminDashboardScreen] / `/admin`.
class OpsKycReviewScreen extends StatelessWidget {
  const OpsKycReviewScreen({super.key});

  @override
  Widget build(BuildContext context) => const AdminDashboardScreen();
}
