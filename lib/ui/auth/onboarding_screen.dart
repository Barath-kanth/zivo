import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hyperlocal/blocs/auth/auth_bloc.dart';
import 'package:hyperlocal/core/constants/app_colors.dart';
import 'package:hyperlocal/core/constants/app_text_styles.dart';
import 'package:hyperlocal/core/constants/community_guidelines.dart';
import 'package:hyperlocal/core/router/app_router.dart';
import 'package:hyperlocal/core/utils/nic_validator.dart';
import 'package:hyperlocal/data/models/user_profile.dart';
import 'package:hyperlocal/data/repositories/profile_repository.dart';
import 'package:image_picker/image_picker.dart';

/// Multi-step trust onboarding: Identity → Documents → Guidelines → Done.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _nicCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _picker = ImagePicker();

  int _step = 0;
  DateTime? _dob;
  String _roleIntent = 'both';
  bool _guidelinesAccepted = false;
  bool _submitting = false;
  /// When verified, identity fields stay locked until user requests a change.
  bool _requestChange = false;
  bool _wasVerified = false;
  String? _nicPath;
  String? _selfiePath;
  String? _avatarPath;
  final List<String> _selectedSkills = [];

  final _skills = const [
    'Errands',
    'Moving Help',
    'Cleaning',
    'Cooking',
    'Tech Support',
    'Tutoring',
    'Pet Care',
    'Queue Standing',
  ];

  String? _kycStatusBanner;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _prefillFromProfile());
  }

  void _prefillFromProfile() {
    final auth = context.read<AuthBloc>().state;
    if (auth is! AuthAuthenticated) return;
    final p = auth.profile;
    setState(() {
      if (p.fullName.trim().isNotEmpty) _nameCtrl.text = p.fullName;
      if (p.homeAddress != null && p.homeAddress!.isNotEmpty) {
        _addressCtrl.text = p.homeAddress!;
      }
      if (p.nicNumber != null && p.nicNumber!.isNotEmpty) {
        _nicCtrl.text = p.nicNumber!;
      }
      if (p.dateOfBirth != null) _dob = p.dateOfBirth;
      if (p.roleIntent.isNotEmpty) _roleIntent = p.roleIntent;
      if (p.helperBio != null) _bioCtrl.text = p.helperBio!;
      if (p.helperSkills.isNotEmpty) {
        _selectedSkills
          ..clear()
          ..addAll(p.helperSkills);
      }
      if (p.avatarUrl != null && p.avatarUrl!.isNotEmpty) {
        _avatarPath = p.avatarUrl;
      }
      if (p.nicImageUrl != null && p.nicImageUrl!.isNotEmpty) {
        _nicPath = p.nicImageUrl;
      }
      if (p.selfieImageUrl != null && p.selfieImageUrl!.isNotEmpty) {
        _selfiePath = p.selfieImageUrl;
      }
      if (p.guidelinesAcceptedAt != null) _guidelinesAccepted = true;

      _wasVerified = p.isKycVerified;
      _requestChange = false;

      if (p.isKycPending) {
        _kycStatusBanner =
            'Documents under review by Zivo Admin. You cannot post or help until approved.';
      } else if (p.isKycVerified) {
        _kycStatusBanner =
            'Verified — name, NIC, address and phone are locked. '
            'To move house or update details, request a change (re-review required).';
      } else if (p.kycStatus == 'rejected') {
        _kycStatusBanner = p.kycRejectionReason != null
            ? 'KYC rejected: ${p.kycRejectionReason}. Please resubmit.'
            : 'KYC rejected. Please update documents and resubmit.';
      }
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _nicCtrl.dispose();
    _bioCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDoc(String type) async {
    if (_fieldsLocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Identity is locked. Tap “Request identity / address change” first.',
          ),
        ),
      );
      return;
    }
    final auth = context.read<AuthBloc>().state;
    String? userId;
    if (auth is AuthNeedsOnboarding) userId = auth.userId;
    if (auth is AuthAuthenticated) userId = auth.profile.id;
    if (userId == null || userId.isEmpty || userId.startsWith('demo-')) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sign in required to upload documents'),
          backgroundColor: AppColors.errorColor,
        ),
      );
      return;
    }

    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final docType = type == 'nic'
          ? 'nic_front'
          : type == 'selfie'
              ? 'selfie'
              : 'avatar';
      final path = await context.read<ProfileRepository>().uploadKycDocument(
            userId: userId,
            docType: docType,
            bytes: bytes,
          );
      setState(() {
        if (type == 'nic') {
          _nicPath = path;
        } else if (type == 'selfie') {
          _selfiePath = path;
        } else {
          _avatarPath = path;
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Upload failed: $e'),
          backgroundColor: AppColors.errorColor,
        ),
      );
    }
  }

  bool _validateStep() {
    if (_step == 0) {
      if (!(_formKey.currentState?.validate() ?? false)) return false;
      if (_dob == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Date of birth is required')),
        );
        return false;
      }
      final age = DateTime.now().difference(_dob!).inDays ~/ 365;
      if (age < 18) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You must be 18 or older')),
        );
        return false;
      }
      return true;
    }
    if (_step == 1) {
      if (_avatarPath == null || _nicPath == null || _selfiePath == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Profile photo, NIC photo, and selfie are all required',
            ),
          ),
        );
        return false;
      }
      return true;
    }
    if (_step == 2) {
      if (!_guidelinesAccepted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Accept the community guidelines to continue'),
          ),
        );
        return false;
      }
      return true;
    }
    return true;
  }

  Future<void> _next() async {
    if (!_validateStep()) return;
    if (_step < 2) {
      setState(() => _step++);
      return;
    }
    await _submit();
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      final repo = context.read<ProfileRepository>();
      final UserProfile profile;
      if (_wasVerified || _requestChange) {
        profile = await repo.requestIdentityChange(
          fullName: _nameCtrl.text.trim(),
          homeAddress: _addressCtrl.text.trim(),
          nicNumber: _nicCtrl.text.trim(),
          dateOfBirth: _dob!,
          avatarUrl: _avatarPath!,
          nicImageUrl: _nicPath!,
          selfieImageUrl: _selfiePath!,
          helperBio:
              _bioCtrl.text.trim().isEmpty ? null : _bioCtrl.text.trim(),
          helperSkills: _selectedSkills,
        );
      } else {
        profile = await repo.submitKyc(
          fullName: _nameCtrl.text.trim(),
          nicNumber: _nicCtrl.text.trim(),
          dateOfBirth: _dob!,
          roleIntent: _roleIntent,
          avatarUrl: _avatarPath!,
          nicImageUrl: _nicPath!,
          selfieImageUrl: _selfiePath!,
          helperBio:
              _bioCtrl.text.trim().isEmpty ? null : _bioCtrl.text.trim(),
          helperSkills: _selectedSkills,
        );
        // Persist address after first KYC without forcing re-review.
        if (_addressCtrl.text.trim().isNotEmpty) {
          try {
            await repo.updateHomeAddress(_addressCtrl.text.trim());
          } catch (_) {}
        }
      }

      if (!mounted) return;
      final authBloc = context.read<AuthBloc>();
      authBloc.add(AuthOnboardingCompleted(profile));
      if (authBloc.state is! AuthAuthenticated) {
        await authBloc.stream.firstWhere((s) => s is AuthAuthenticated);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            profile.isKycVerified
                ? 'Identity verified. Welcome!'
                : 'Submitted for Zivo Admin review. Posting and Helper stay locked until approved.',
          ),
          backgroundColor: AppColors.successColor,
          duration: const Duration(seconds: 4),
        ),
      );
      context.go(AppRoutes.shell);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$e'),
          backgroundColor: AppColors.errorColor,
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  bool get _fieldsLocked => _wasVerified && !_requestChange;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () {
                          if (context.canPop()) {
                            context.pop();
                          } else {
                            context.go(AppRoutes.shell);
                          }
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
                      Expanded(child: _buildProgress()),
                    ],
                  ),
                  if (_kycStatusBanner != null) ...[
                    const Gap(12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.warningColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _kycStatusBanner!,
                        style: AppTextStyles.bodySmall.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                child: Form(
                  key: _formKey,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: _step == 0
                        ? _buildIdentityStep()
                        : _step == 1
                            ? _buildDocumentsStep()
                            : _buildGuidelinesStep(),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Row(
                children: [
                  if (_step > 0)
                    TextButton(
                      onPressed: _submitting
                          ? null
                          : () => setState(() => _step--),
                      child: const Text('Back'),
                    ),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: _submitting ? null : _next,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            _step == 2 ? 'Submit for verification' : 'Continue',
                            style: AppTextStyles.buttonLabel,
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgress() {
    return Row(
      children: List.generate(3, (i) {
        return Expanded(
          child: Container(
            height: 5,
            margin: EdgeInsets.only(right: i < 2 ? 6 : 0),
            decoration: BoxDecoration(
              color: i <= _step
                  ? AppColors.accent
                  : AppColors.accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildIdentityStep() {
    return Column(
      key: const ValueKey('identity'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Verify your identity', style: AppTextStyles.displayMedium)
            .animate()
            .fadeIn(),
        const Gap(6),
        Text(
          'Legal name and NIC must match. This prevents impersonation and keeps Hyperlocal credible under Sri Lankan law.',
          style: AppTextStyles.bodyMedium,
        ),
        const Gap(24),
        TextFormField(
          controller: _nameCtrl,
          readOnly: _fieldsLocked,
          textCapitalization: TextCapitalization.words,
          style: AppTextStyles.bodyLarge,
          decoration: const InputDecoration(
            labelText: 'Full legal name',
            prefixIcon: Icon(Icons.person_outline, color: AppColors.textMuted),
          ),
          validator: (v) =>
              (v == null || v.trim().length < 2) ? 'Name is required' : null,
        ),
        const Gap(16),
        TextFormField(
          controller: _addressCtrl,
          readOnly: _fieldsLocked,
          textCapitalization: TextCapitalization.sentences,
          style: AppTextStyles.bodyLarge,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Home address',
            hintText: 'Street, city — used for trust & safety',
            prefixIcon: Icon(Icons.home_outlined, color: AppColors.textMuted),
          ),
          validator: (v) =>
              (v == null || v.trim().length < 5) ? 'Address is required' : null,
        ),
        if (_wasVerified) ...[
          const Gap(12),
          if (!_requestChange)
            OutlinedButton.icon(
              onPressed: () {
                setState(() {
                  _requestChange = true;
                  _kycStatusBanner =
                      'Editing unlocked. After you save, status returns to Pending until Admin re-approves. Posting/Helper stay locked until then.';
                });
              },
              icon: const Icon(Icons.lock_open_outlined),
              label: const Text('Request identity / address change'),
            )
          else
            Text(
              'Change mode: saving will set status to Pending for Admin re-review.',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.warningColor,
              ),
            ),
        ],
        const Gap(16),
        TextFormField(
          controller: _nicCtrl,
          readOnly: _fieldsLocked,
          textCapitalization: TextCapitalization.characters,
          style: AppTextStyles.bodyLarge,
          decoration: const InputDecoration(
            labelText: 'NIC number',
            hintText: 'NIC number (12 digits or old format with V/X)',
            prefixIcon: Icon(Icons.badge_outlined, color: AppColors.textMuted),
          ),
          validator: NicValidator.validateMessage,
        ),
        const Gap(16),
        ListTile(
          contentPadding: EdgeInsets.zero,
          enabled: !_fieldsLocked,
          title: Text(
            _dob == null
                ? 'Date of birth'
                : 'DOB: ${_dob!.toLocal().toString().split(' ').first}',
            style: AppTextStyles.bodyLarge,
          ),
          subtitle: const Text('Must be 18+'),
          trailing: const Icon(Icons.calendar_today_outlined),
          onTap: _fieldsLocked
              ? null
              : () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: DateTime(2000, 1, 1),
                    firstDate: DateTime(1940),
                    lastDate: DateTime.now()
                        .subtract(const Duration(days: 365 * 18)),
                  );
                  if (picked != null) setState(() => _dob = picked);
                },
        ),
        const Gap(12),
        Text('I want to use Hyperlocal as', style: AppTextStyles.labelLarge),
        const Gap(8),
        Wrap(
          spacing: 8,
          children: [
            for (final opt in [
              ('client', 'Client'),
              ('helper', 'Helper'),
              ('both', 'Both'),
            ])
              ChoiceChip(
                label: Text(opt.$2),
                selected: _roleIntent == opt.$1,
                onSelected: (_) => setState(() => _roleIntent = opt.$1),
              ),
          ],
        ),
        if (_roleIntent != 'client') ...[
          const Gap(16),
          TextFormField(
            controller: _bioCtrl,
            maxLines: 2,
            style: AppTextStyles.bodyLarge,
            decoration: const InputDecoration(
              labelText: 'Helper bio (optional)',
            ),
          ),
          const Gap(12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _skills.map((s) {
              final sel = _selectedSkills.contains(s);
              return FilterChip(
                label: Text(s),
                selected: sel,
                onSelected: (v) {
                  setState(() {
                    if (v) {
                      _selectedSkills.add(s);
                    } else {
                      _selectedSkills.remove(s);
                    }
                  });
                },
              );
            }).toList(),
          ),
        ],
      ],
    );
  }

  Widget _buildDocumentsStep() {
    return Column(
      key: const ValueKey('docs'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Photos & documents', style: AppTextStyles.displayMedium),
        const Gap(6),
        Text(
          'Profile photo is mandatory and shown to others. NIC + selfie are private — our review team matches them before Helper mode unlocks.',
          style: AppTextStyles.bodyMedium,
        ),
        const Gap(24),
        Center(
          child: Column(
            children: [
              GestureDetector(
                onTap: () => _pickDoc('avatar'),
                child: CircleAvatar(
                  radius: 48,
                  backgroundColor: AppColors.surfaceDark,
                  child: _avatarPath == null
                      ? const Icon(Icons.add_a_photo_outlined,
                          size: 32, color: AppColors.textMuted)
                      : const Icon(Icons.check_circle,
                          size: 40, color: AppColors.successColor),
                ),
              ),
              const Gap(8),
              Text(
                _avatarPath == null
                    ? 'Add profile photo (required)'
                    : 'Profile photo added',
                style: AppTextStyles.labelLarge.copyWith(
                  color: _avatarPath == null
                      ? AppColors.errorColor
                      : AppColors.successColor,
                ),
              ),
            ],
          ),
        ),
        const Gap(24),
        _docTile(
          title: 'NIC photo',
          subtitle: _nicPath == null ? 'Required — clear front of NIC' : 'Uploaded',
          done: _nicPath != null,
          onTap: () => _pickDoc('nic'),
        ),
        const Gap(12),
        _docTile(
          title: 'Live selfie',
          subtitle: _selfiePath == null
              ? 'Required — must match NIC face'
              : 'Uploaded',
          done: _selfiePath != null,
          onTap: () => _pickDoc('selfie'),
        ),
        const Gap(16),
        Text(
          'How we verify: Hyperlocal ops compares profile photo + selfie + NIC name/number. Status stays pending until approved. Fake docs = ban.',
          style: AppTextStyles.bodySmall.copyWith(color: AppColors.textMuted),
        ),
      ],
    );
  }

  Widget _docTile({
    required String title,
    required String subtitle,
    required bool done,
    required VoidCallback onTap,
  }) {
    return ListTile(
      onTap: onTap,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: done ? AppColors.successColor : AppColors.borderColor,
        ),
      ),
      leading: Icon(
        done ? Icons.check_circle : Icons.upload_file_outlined,
        color: done ? AppColors.successColor : AppColors.textMuted,
      ),
      title: Text(title, style: AppTextStyles.labelLarge),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
    );
  }

  Widget _buildGuidelinesStep() {
    return Column(
      key: const ValueKey('guidelines'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(CommunityGuidelines.title, style: AppTextStyles.displayMedium),
        const Gap(6),
        Text(
          'Version ${CommunityGuidelines.currentVersion} — Uber-style community standards adapted for Hyperlocal in Sri Lanka.',
          style: AppTextStyles.bodySmall,
        ),
        const Gap(16),
        Container(
          height: 280,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surfaceDark,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.borderColor),
          ),
          child: SingleChildScrollView(
            child: Text(
              CommunityGuidelines.bodyMd,
              style: AppTextStyles.bodySmall.copyWith(height: 1.45),
            ),
          ),
        ),
        const Gap(16),
        CheckboxListTile(
          value: _guidelinesAccepted,
          onChanged: (v) => setState(() => _guidelinesAccepted = v ?? false),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          title: Text(
            'I confirm I am 18+, my NIC is genuine, and I will not post or accept unlawful tasks.',
            style: AppTextStyles.bodyMedium,
          ),
        ),
      ],
    );
  }
}
