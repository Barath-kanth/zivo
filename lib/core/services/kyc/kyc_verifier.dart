/// Pluggable KYC verifier — real providers (Jumio/Onfido/etc.) implement this later.
abstract class KycVerifier {
  /// Called after documents are submitted. Stub leaves status as `pending`.
  Future<KycVerificationOutcome> submitForReview({
    required String userId,
    required String nicNumber,
    required String nicImageUrl,
    required String selfieImageUrl,
  });
}

class KycVerificationOutcome {
  const KycVerificationOutcome({
    required this.status,
    this.providerReference,
    this.message,
  });

  /// pending | verified | rejected
  final String status;
  final String? providerReference;
  final String? message;
}

/// Default verifier: queues for manual/admin review (no auto-approve).
class StubKycVerifier implements KycVerifier {
  @override
  Future<KycVerificationOutcome> submitForReview({
    required String userId,
    required String nicNumber,
    required String nicImageUrl,
    required String selfieImageUrl,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    return KycVerificationOutcome(
      status: 'pending',
      providerReference: 'stub-${DateTime.now().millisecondsSinceEpoch}',
      message:
          'Documents received. Identity review is pending (StubKycVerifier).',
    );
  }
}
