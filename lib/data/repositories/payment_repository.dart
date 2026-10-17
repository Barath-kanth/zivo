import 'package:hyperlocal/core/services/gcp/gcp_api_client.dart';
import 'package:url_launcher/url_launcher.dart';

class PayHereCheckoutSession {
  const PayHereCheckoutSession({
    required this.checkoutUrl,
    required this.fields,
    required this.orderId,
    required this.amount,
  });

  final String checkoutUrl;
  final Map<String, String> fields;
  final String orderId;
  final String amount;
}

/// Wallet top-up via GCP Cloud Run (PayHere Edge removed).
class PaymentRepository {
  PaymentRepository(this._api);

  final GcpApiClient _api;

  Future<void> mockTopUp({
    required String userId,
    required double amount,
  }) async {
    if (userId.startsWith('demo-')) return;
    await _api.postJson('/wallet/topup', {'amount': amount});
  }

  /// Card top-up via Cloud Run. Full PAN never leaves the client —
  /// only optional brand + last4 are sent for the ledger note.
  Future<String> startTopUp({
    required String userId,
    required double amount,
    String? firstName,
    String? lastName,
    String? email,
    String? phone,
    String? cardBrand,
    String? cardLast4,
  }) async {
    if (userId.startsWith('demo-')) return 'demo_credited';
    await _api.postJson('/wallet/topup', {
      'amount': amount,
      if (cardBrand != null) 'card_brand': cardBrand,
      if (cardLast4 != null) 'card_last4': cardLast4,
    });
    return 'card_credited';
  }

  Future<PayHereCheckoutSession> createPayHereCheckout({
    required double amount,
    String? firstName,
    String? lastName,
    String? email,
    String? phone,
  }) async {
    throw Exception(
      'PayHere removed for Cup. Use in-app Top up (GCP /wallet/topup).',
    );
  }

  Future<void> openCheckoutInBrowser(PayHereCheckoutSession session) async {
    final uri = Uri.parse(session.checkoutUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
