/// Sri Lanka NIC validation — old (9 + V/X) and new (12-digit).
class NicValidator {
  NicValidator._();

  static String normalize(String raw) => raw.trim().toUpperCase().replaceAll(RegExp(r'\s'), '');

  static bool isValid(String raw) {
    final v = normalize(raw);
    if (RegExp(r'^[0-9]{12}$').hasMatch(v)) return true;
    if (RegExp(r'^[0-9]{9}[VX]$').hasMatch(v)) return true;
    return false;
  }

  static String? validateMessage(String? raw) {
    if (raw == null || raw.trim().isEmpty) return 'NIC number is required';
    if (!isValid(raw)) {
      return 'Enter a valid Sri Lanka NIC (12 digits or 9 digits + V/X)';
    }
    return null;
  }

  /// Extract approximate year of birth hint from new-format NIC (first 4 = year).
  static int? birthYearHint(String raw) {
    final v = normalize(raw);
    if (RegExp(r'^[0-9]{12}$').hasMatch(v)) {
      return int.tryParse(v.substring(0, 4));
    }
    if (RegExp(r'^[0-9]{9}[VX]$').hasMatch(v)) {
      final yy = int.tryParse(v.substring(0, 2));
      if (yy == null) return null;
      // Heuristic: 00–25 → 2000s else 1900s (common SL practice for old NIC)
      return yy <= 25 ? 2000 + yy : 1900 + yy;
    }
    return null;
  }
}
