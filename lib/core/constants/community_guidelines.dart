/// Community guidelines seed — version must match DB `community_guidelines`.
abstract class CommunityGuidelines {
  static const String currentVersion = '2026.08.1';

  static const String title =
      'Zivo Community Guidelines (Sri Lanka)';

  static const String bodyMd = '''
# Zivo Community Guidelines — Sri Lanka

These rules keep clients and helpers safe and align with Sri Lankan law and industry community standards (Uber-style credibility for on-demand matching).

## You must

- Be **18+** and use your real legal identity (NIC).
- Complete phone verification (`+94`) before posting or accepting work.
- Complete **KYC verification** before activating Helper mode.
- Treat others with respect; no harassment or discrimination.

## Prohibited (blocked in real time)

- Weapons, explosives, or anything intended to cause harm
- Illegal drugs or controlled substances
- Alcohol purchase/delivery involving minors
- Cash courier / money-mule / hawala / unauthorized money transfer schemes
- Gambling facilitation
- Sexual services or exploitation of any kind
- Impersonation or fake identity documents
- Tasks that facilitate fraud, theft, or identity deception

## Sensitive categories

- Babysitting / child care: Helper must be **KYC verified**.
- Elder care / hospital companion: helpers are not licensed clinicians unless stated.

## Enforcement

Violations are blocked at submit time, logged (content hashed), and may lead to account suspension.
''';
}
