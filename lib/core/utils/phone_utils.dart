/// Sri Lanka phone helpers — E.164 +94XXXXXXXXX (9 national digits after 94).
class PhoneUtils {
  PhoneUtils._();

  static const String countryCode = '+94';

  /// Digits only national number (without leading 0).
  static String nationalDigits(String raw) {
    var digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('94')) digits = digits.substring(2);
    if (digits.startsWith('0')) digits = digits.substring(1);
    return digits;
  }

  /// Normalize to E.164 or return null if invalid.
  static String? toE164(String raw) {
    final national = nationalDigits(raw);
    if (!RegExp(r'^[1-9][0-9]{8}$').hasMatch(national)) return null;
    return '$countryCode$national';
  }

  static bool isValidSriLankaMobile(String raw) => toE164(raw) != null;

  /// Display as +94 77 123 4567
  static String formatDisplay(String e164OrRaw) {
    final e164 = toE164(e164OrRaw) ?? e164OrRaw;
    final n = nationalDigits(e164);
    if (n.length != 9) return e164;
    return '+94 ${n.substring(0, 2)} ${n.substring(2, 5)} ${n.substring(5)}';
  }
}
