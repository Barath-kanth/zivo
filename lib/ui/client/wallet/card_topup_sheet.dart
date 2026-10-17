import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';
import 'package:hyperlocal/core/constants/app_colors.dart';
import 'package:hyperlocal/core/constants/zivo_palette.dart';
import 'package:hyperlocal/core/constants/app_config.dart';
import 'package:hyperlocal/core/constants/app_text_styles.dart';

enum CardBrand { visa, mastercard, amex, unknown }

CardBrand detectCardBrand(String digits) {
  final d = digits.replaceAll(RegExp(r'\D'), '');
  if (d.startsWith('4')) return CardBrand.visa;
  if (RegExp(r'^5[1-5]').hasMatch(d) || RegExp(r'^2[2-7]').hasMatch(d)) {
    return CardBrand.mastercard;
  }
  if (d.startsWith('34') || d.startsWith('37')) return CardBrand.amex;
  return CardBrand.unknown;
}

bool luhnValid(String digits) {
  final d = digits.replaceAll(RegExp(r'\D'), '');
  if (d.length < 13) return false;
  var sum = 0;
  var alt = false;
  for (var i = d.length - 1; i >= 0; i--) {
    var n = int.parse(d[i]);
    if (alt) {
      n *= 2;
      if (n > 9) n -= 9;
    }
    sum += n;
    alt = !alt;
  }
  return sum % 10 == 0;
}

class CardTopUpResult {
  const CardTopUpResult({
    required this.amount,
    required this.brand,
    required this.last4,
  });
  final double amount;
  final CardBrand brand;
  final String last4;
}

/// Card top-up sheet — Visa / Mastercard / Amex. Full PAN never leaves the device;
/// only brand + last4 + amount are returned for the wallet credit call.
Future<CardTopUpResult?> showCardTopUpSheet(BuildContext context) {
  return showModalBottomSheet<CardTopUpResult>(
    context: context,
    isScrollControlled: true,
    // Cover the shell bottom dock so Pay & top up is never clipped.
    useRootNavigator: true,
    useSafeArea: true,
    backgroundColor: ZivoPalette.of(context).card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => const _CardTopUpSheet(),
  );
}

class _CardTopUpSheet extends StatefulWidget {
  const _CardTopUpSheet();

  @override
  State<_CardTopUpSheet> createState() => _CardTopUpSheetState();
}

class _CardTopUpSheetState extends State<_CardTopUpSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController(text: '2500');
  final _nameCtrl = TextEditingController();
  final _numberCtrl = TextEditingController();
  final _expiryCtrl = TextEditingController();
  final _cvvCtrl = TextEditingController();
  CardBrand _brand = CardBrand.unknown;
  bool _submitting = false;

  static const _presets = [1000.0, 2500.0, 5000.0, 10000.0];

  @override
  void dispose() {
    _amountCtrl.dispose();
    _nameCtrl.dispose();
    _numberCtrl.dispose();
    _expiryCtrl.dispose();
    _cvvCtrl.dispose();
    super.dispose();
  }

  String get _digits => _numberCtrl.text.replaceAll(RegExp(r'\D'), '');

  void _onNumberChanged(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    final brand = detectCardBrand(digits);
    final buf = StringBuffer();
    if (brand == CardBrand.amex) {
      for (var i = 0; i < digits.length && i < 15; i++) {
        if (i == 4 || i == 10) buf.write(' ');
        buf.write(digits[i]);
      }
    } else {
      for (var i = 0; i < digits.length && i < 16; i++) {
        if (i > 0 && i % 4 == 0) buf.write(' ');
        buf.write(digits[i]);
      }
    }
    final formatted = buf.toString();
    if (formatted != raw) {
      _numberCtrl.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    }
    setState(() => _brand = brand);
  }

  void _onExpiryChanged(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    final buf = StringBuffer();
    for (var i = 0; i < digits.length && i < 4; i++) {
      if (i == 2) buf.write('/');
      buf.write(digits[i]);
    }
    final formatted = buf.toString();
    if (formatted != raw) {
      _expiryCtrl.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    }
  }

  String? _validateNumber(String? _) {
    final d = _digits;
    final brand = detectCardBrand(d);
    if (brand == CardBrand.unknown) {
      return 'Enter a Visa, Mastercard, or Amex number';
    }
    final need = brand == CardBrand.amex ? 15 : 16;
    if (d.length != need) return 'Card number looks incomplete';
    if (!luhnValid(d)) return 'Card number is invalid';
    return null;
  }

  String? _validateExpiry(String? v) {
    final m = RegExp(r'^(\d{2})/(\d{2})$').firstMatch((v ?? '').trim());
    if (m == null) return 'Use MM/YY';
    final month = int.parse(m.group(1)!);
    final year = 2000 + int.parse(m.group(2)!);
    if (month < 1 || month > 12) return 'Invalid month';
    final now = DateTime.now();
    final exp = DateTime(year, month + 1, 0);
    if (exp.isBefore(DateTime(now.year, now.month, 1))) {
      return 'Card expired';
    }
    return null;
  }

  String? _validateCvv(String? v) {
    final d = (v ?? '').replaceAll(RegExp(r'\D'), '');
    final need = _brand == CardBrand.amex ? 4 : 3;
    if (d.length != need) return 'CVV is $need digits';
    return null;
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final amount = double.tryParse(_amountCtrl.text.trim());
    if (amount == null || amount < 100) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Minimum top-up is LKR 100')),
      );
      return;
    }
    setState(() => _submitting = true);
    // Brief authorize UX — PAN stays on device only.
    await Future<void>.delayed(const Duration(milliseconds: 650));
    if (!mounted) return;
    final last4 = _digits.substring(_digits.length - 4);
    Navigator.pop(
      context,
      CardTopUpResult(amount: amount, brand: _brand, last4: last4),
    );
  }

  Widget _brandChip(CardBrand brand, String label, Color color) {
    final on = _brand == brand;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: on ? color.withValues(alpha: 0.12) : ZivoPalette.of(context).surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: on ? color : ZivoPalette.of(context).border,
          width: on ? 1.5 : 1,
        ),
      ),
      child: Text(
        label,
        style: AppTextStyles.bodySmall.copyWith(
          fontWeight: FontWeight.w700,
          color: on ? color : ZivoPalette.of(context).textMuted,
          fontSize: 11,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        16,
        24,
        20 + keyboard + safeBottom,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: ZivoPalette.of(context).border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Gap(18),
              Text(
                'Top up with card',
                style: AppTextStyles.headingMedium.copyWith(
                  color: ZivoPalette.of(context).textPrimary,
                ),
              ),
              const Gap(4),
              Text(
                'Visa, Mastercard, or Amex. Card details stay on this device.',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: ZivoPalette.of(context).textSecondary,
                ),
              ),
              const Gap(12),
              Row(
                children: [
                  _brandChip(CardBrand.visa, 'Visa', const Color(0xFF1A1F71)),
                  const Gap(8),
                  _brandChip(
                      CardBrand.mastercard, 'Mastercard', const Color(0xFFEB001B)),
                  const Gap(8),
                  _brandChip(CardBrand.amex, 'Amex', const Color(0xFF006FCF)),
                ],
              ),
              const Gap(16),
              Text(
                'Amount (LKR)',
                style: AppTextStyles.bodySmall.copyWith(
                  color: ZivoPalette.of(context).textPrimary,
                ),
              ),
              const Gap(8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _presets
                    .map(
                      (amt) => ChoiceChip(
                        label: Text(AppConfig.money(amt, decimals: 0)),
                        selected: _amountCtrl.text == amt.toStringAsFixed(0),
                        onSelected: (_) {
                          setState(() {
                            _amountCtrl.text = amt.toStringAsFixed(0);
                          });
                        },
                      ),
                    )
                    .toList(),
              ),
              const Gap(8),
              TextFormField(
                controller: _amountCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Custom amount',
                  prefixText: 'LKR ',
                ),
                validator: (v) {
                  final n = double.tryParse((v ?? '').trim());
                  if (n == null || n < 100) return 'Min LKR 100';
                  return null;
                },
              ),
              const Gap(12),
              TextFormField(
                controller: _nameCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Name on card',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
                validator: (v) =>
                    (v == null || v.trim().length < 2) ? 'Enter cardholder name' : null,
              ),
              const Gap(10),
              TextFormField(
                controller: _numberCtrl,
                keyboardType: TextInputType.number,
                onChanged: _onNumberChanged,
                decoration: const InputDecoration(
                  labelText: 'Card number',
                  prefixIcon: Icon(Icons.credit_card_rounded),
                  hintText: '•••• •••• •••• ••••',
                ),
                validator: _validateNumber,
              ),
              const Gap(10),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _expiryCtrl,
                      keyboardType: TextInputType.number,
                      onChanged: _onExpiryChanged,
                      decoration: const InputDecoration(
                        labelText: 'Expiry',
                        hintText: 'MM/YY',
                      ),
                      validator: _validateExpiry,
                    ),
                  ),
                  const Gap(12),
                  Expanded(
                    child: TextFormField(
                      controller: _cvvCtrl,
                      keyboardType: TextInputType.number,
                      obscureText: true,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(4),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'CVV',
                        hintText: '•••',
                      ),
                      validator: _validateCvv,
                    ),
                  ),
                ],
              ),
              const Gap(20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(52),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Pay & top up'),
                ),
              ),
              const Gap(10),
              Text(
                'Secured card entry · only last 4 digits are sent with your top-up.',
                style: AppTextStyles.bodySmall.copyWith(color: ZivoPalette.of(context).textMuted),
              ),
              const Gap(8),
            ],
          ),
        ),
      ),
    );
  }
}
