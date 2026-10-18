import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Result of a real-time community policy check.
class PolicyCheckResult {
  const PolicyCheckResult.allowed()
      : allowed = true,
        matchedRule = null,
        userMessage = null;

  const PolicyCheckResult.blocked({
    required this.matchedRule,
    required this.userMessage,
  }) : allowed = false;

  final bool allowed;
  final String? matchedRule;
  final String? userMessage;
}

/// Client-side mirror of SQL `check_task_policy`.
/// Blocks unlawful / high-risk Hyperlocal task content (SL + Uber-style standards).
class CommunityPolicyEngine {
  static final List<_PolicyRule> _rules = [
    _PolicyRule(
      id: 'weapons_explosives',
      pattern: RegExp(
        r'weapon|gun|pistol|rifle|explosive|bomb|grenade|ammunition|knife fight',
        caseSensitive: false,
      ),
      message:
          'Weapons and explosives are prohibited under Sri Lankan law and Hyperlocal guidelines.',
    ),
    _PolicyRule(
      id: 'illegal_drugs',
      pattern: RegExp(
        r'cocaine|heroin|meth|cannabis|weed|ganja|mdma|ecstasy|illegal drug|narcotic',
        caseSensitive: false,
      ),
      message:
          'Controlled substances and illegal drugs are not allowed on Hyperlocal.',
    ),
    _PolicyRule(
      id: 'alcohol_minors',
      pattern: RegExp(
        r'buy alcohol for|beer for minor|liquor for under|arrack for kid',
        caseSensitive: false,
      ),
      message: 'Alcohol-related tasks involving minors are prohibited.',
    ),
    _PolicyRule(
      id: 'cash_to_helper_goods',
      pattern: RegExp(
        r'give cash to helper|hand cash|cash for groceries|pay helper in cash for|give money to buy|float cash|petty cash to helper',
        caseSensitive: false,
      ),
      message:
          'Never give cash to helpers for goods. Escrow a goods budget; helpers are reimbursed only against a supermarket receipt and photos.',
    ),
    _PolicyRule(
      id: 'cash_fraud',
      pattern: RegExp(
        r'cash delivery|cash courier|money mule|hawala|undial|unauthorized transfer|bank otp|sim swap',
        caseSensitive: false,
      ),
      message:
          'Cash courier, money-mule, and unauthorized transfer requests are blocked.',
    ),
    _PolicyRule(
      id: 'gambling',
      pattern: RegExp(
        r'gambling|casino|betting|bookie|lottery scam',
        caseSensitive: false,
      ),
      message: 'Gambling facilitation is not allowed.',
    ),
    _PolicyRule(
      id: 'sexual_exploitation',
      pattern: RegExp(
        r'escort|sexual service|prostitution|onlyfans meetup|sex work',
        caseSensitive: false,
      ),
      message: 'Sexual services and exploitation are strictly prohibited.',
    ),
    _PolicyRule(
      id: 'impersonation',
      pattern: RegExp(
        r'fake nic|forged nic|fake id|impersonat|stolen identity',
        caseSensitive: false,
      ),
      message: 'Impersonation and fake identity requests are blocked.',
    ),
    _PolicyRule(
      id: 'secret_handoff',
      pattern: RegExp(
        r"no questions( asked)?|don'?t ask (what('?s| is) (inside|in it)|anything|questions?)|do not ask (what('?s| is) (inside|in it)|anything|questions?)|without asking (anything|questions?)|don'?t (look|open|check) (inside|it)|keep it (secret|discreet)|discreet (delivery|package|parcel)|((parcel|package|envelope|packet).{0,60}(without asking|don'?t ask|do not ask|no questions)|(without asking|don'?t ask|do not ask|no questions).{0,60}(parcel|package|envelope|packet))|கேட்காமல்|අහන්නැතුව|රහස්\s?(පාර්සල්|පැකේජ්)",
        caseSensitive: false,
      ),
      message:
          'Secret / “no questions” parcel handoffs are not allowed. Describe an ordinary neighbourhood errand, or this request stays blocked.',
    ),
  ];

  static PolicyCheckResult evaluate({
    required String title,
    required String description,
  }) {
    final text = '$title $description';
    for (final rule in _rules) {
      if (rule.pattern.hasMatch(text)) {
        return PolicyCheckResult.blocked(
          matchedRule: rule.id,
          userMessage: rule.message,
        );
      }
    }
    return const PolicyCheckResult.allowed();
  }

  /// SHA-256 hex of snippet for violation logs (never store raw illegal text long-term).
  static String hashSnippet(String snippet) {
    return sha256.convert(utf8.encode(snippet)).toString();
  }

  static bool categoryRequiresVerifiedKyc(String categoryName) {
    final c = categoryName.toLowerCase();
    return c == 'babysitting' || c == 'eldercare' || c == 'care';
  }
}

class _PolicyRule {
  const _PolicyRule({
    required this.id,
    required this.pattern,
    required this.message,
  });
  final String id;
  final RegExp pattern;
  final String message;
}
