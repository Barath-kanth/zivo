import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:hyperlocal/blocs/auth/auth_bloc.dart';
import 'package:hyperlocal/core/constants/app_colors.dart';
import 'package:hyperlocal/core/constants/zivo_palette.dart';
import 'package:hyperlocal/core/constants/app_text_styles.dart';
import 'package:hyperlocal/data/models/helper_qualification.dart';
import 'package:hyperlocal/data/repositories/profile_repository.dart';
import 'package:hyperlocal/data/repositories/trust_repository.dart';
import 'package:image_picker/image_picker.dart';

class QualificationsScreen extends StatefulWidget {
  const QualificationsScreen({super.key});

  @override
  State<QualificationsScreen> createState() => _QualificationsScreenState();
}

class _QualificationsScreenState extends State<QualificationsScreen> {
  List<HelperQualification> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final auth = context.read<AuthBloc>().state;
    if (auth is! AuthAuthenticated) return;
    final list =
        await context.read<TrustRepository>().getQualifications(auth.profile.id);
    if (!mounted) return;
    setState(() {
      _items = list;
      _loading = false;
    });
  }

  Future<void> _openAddSheet() async {
    final auth = context.read<AuthBloc>().state;
    if (auth is! AuthAuthenticated) return;

    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      enableDrag: true,
      isDismissible: true,
      useSafeArea: true,
      backgroundColor: AppColors.cardDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _AddQualificationSheet(
        userId: auth.profile.id,
        onClose: () => Navigator.pop(ctx, false),
        onSubmitted: () => Navigator.pop(ctx, true),
      ),
    );

    if (submitted == true && mounted) {
      await _refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Submitted — pending Hyperlocal review (not auto-approved).',
          ),
          backgroundColor: AppColors.successColor,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZivoPalette.of(context).canvas,
      appBar: AppBar(
        title: Text('Qualifications', style: AppTextStyles.headingMedium),
        backgroundColor: ZivoPalette.of(context).canvas,
        actions: [
          IconButton(
            onPressed: _openAddSheet,
            icon: const Icon(Icons.add),
            tooltip: 'Add',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddSheet,
        backgroundColor: AppColors.accent,
        icon: const Icon(Icons.add, color: Colors.white),
        label: Text(
          'Add credential',
          style: AppTextStyles.buttonLabel.copyWith(color: Colors.white),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Add a driving licence before Driver jobs, teaching credentials for Tutoring, and care training for Babysitting / Elder Care. Unverified claims are not trusted.',
                          style: AppTextStyles.bodyMedium,
                          textAlign: TextAlign.center,
                        ),
                        const Gap(20),
                        ElevatedButton.icon(
                          onPressed: _openAddSheet,
                          icon: const Icon(Icons.upload_file, color: Colors.white),
                          label: Text(
                            'Add your first document',
                            style: AppTextStyles.buttonLabel
                                .copyWith(color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => const Gap(10),
                  itemBuilder: (ctx, i) {
                    final q = _items[i];
                    final color = q.isVerified
                        ? AppColors.successColor
                        : q.isPending
                            ? AppColors.warningColor
                            : AppColors.errorColor;
                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: ZivoPalette.of(context).surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.borderColor),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(q.title,
                                    style: AppTextStyles.labelLarge),
                              ),
                              Text(
                                q.status.toUpperCase(),
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: color,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                          const Gap(4),
                          Text(q.type.label, style: AppTextStyles.bodySmall),
                          if (q.issuer != null) ...[
                            const Gap(2),
                            Text('Issuer: ${q.issuer}',
                                style: AppTextStyles.bodySmall),
                          ],
                          if (q.documentPath != null) ...[
                            const Gap(6),
                            Row(
                              children: [
                                Icon(Icons.attach_file,
                                    size: 14, color: ZivoPalette.of(context).textMuted),
                                const Gap(4),
                                Expanded(
                                  child: Text(
                                    'Document on file',
                                    style: AppTextStyles.bodySmall.copyWith(
                                      color: AppColors.successColor,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          if (q.rejectionReason != null) ...[
                            const Gap(6),
                            Text(
                              q.rejectionReason!,
                              style: AppTextStyles.bodySmall
                                  .copyWith(color: AppColors.errorColor),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}

class _AddQualificationSheet extends StatefulWidget {
  const _AddQualificationSheet({
    required this.userId,
    required this.onClose,
    required this.onSubmitted,
  });

  final String userId;
  final VoidCallback onClose;
  final VoidCallback onSubmitted;

  @override
  State<_AddQualificationSheet> createState() => _AddQualificationSheetState();
}

class _AddQualificationSheetState extends State<_AddQualificationSheet> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _issuerCtrl = TextEditingController();
  final _credCtrl = TextEditingController();
  final _picker = ImagePicker();

  QualificationType _type = QualificationType.drivingLicence;
  String? _docPath;
  String? _docLabel;
  Uint8List? _previewBytes;
  bool _submitting = false;
  bool _picking = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _issuerCtrl.dispose();
    _credCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDocument() async {
    setState(() => _picking = true);
    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 2000,
        imageQuality: 85,
      );
      if (file == null) {
        setState(() => _picking = false);
        return;
      }
      final bytes = await file.readAsBytes();
      if (widget.userId.startsWith('demo-')) {
        throw Exception('Demo disabled');
      }
      final path = await context.read<ProfileRepository>().uploadKycDocument(
            userId: widget.userId,
            docType: 'qual_${_type.dbValue}',
            bytes: bytes,
          );
      if (!mounted) return;
      setState(() {
        _docPath = path;
        _docLabel = file.name;
        _previewBytes = bytes;
        _picking = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _picking = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not attach document: $e'),
          backgroundColor: AppColors.errorColor,
        ),
      );
    }
  }

  void _clearDocument() {
    setState(() {
      _docPath = null;
      _docLabel = null;
      _previewBytes = null;
    });
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_type.requiresDocument && (_docPath == null || _docPath!.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please attach a document photo for this type'),
          backgroundColor: AppColors.errorColor,
        ),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      await context.read<TrustRepository>().submitQualification(
            userId: widget.userId,
            type: _type,
            title: _titleCtrl.text.trim(),
            issuer: _issuerCtrl.text.trim().isEmpty
                ? null
                : _issuerCtrl.text.trim(),
            credentialId: _credCtrl.text.trim().isEmpty
                ? null
                : _credCtrl.text.trim(),
            documentPath: _docPath,
          );
      if (!mounted) return;
      widget.onSubmitted();
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$e'),
          backgroundColor: AppColors.errorColor,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.88,
        child: Column(
          children: [
            // Handle + close
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Row(
                children: [
                  const SizedBox(width: 48),
                  Expanded(
                    child: Column(
                      children: [
                        Container(
                          width: 40,
                          height: 4,
                          margin: const EdgeInsets.only(top: 6, bottom: 10),
                          decoration: BoxDecoration(
                            color: AppColors.borderColor,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        Text('Add qualification',
                            style: AppTextStyles.headingMedium),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: _submitting ? null : widget.onClose,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                  children: [
                    Text(
                      'Upload only genuine documents in your name. Fake credentials are illegal and will get the account banned.',
                      style: AppTextStyles.bodySmall,
                    ),
                    const Gap(16),
                    DropdownButtonFormField<QualificationType>(
                      value: _type,
                      items: QualificationType.values
                          .map(
                            (t) => DropdownMenuItem(
                              value: t,
                              child: Text(t.label),
                            ),
                          )
                          .toList(),
                      onChanged: _submitting
                          ? null
                          : (v) {
                              if (v != null) {
                                setState(() {
                                  _type = v;
                                  // Clear doc when type changes so user re-attaches
                                  if (_docPath != null &&
                                      !(_docPath!.contains(v.dbValue))) {
                                    // keep attached; only update hint
                                  }
                                });
                              }
                            },
                      decoration: const InputDecoration(labelText: 'Type'),
                    ),
                    const Gap(8),
                    Text(_type.hint, style: AppTextStyles.bodySmall),
                    const Gap(14),
                    TextFormField(
                      controller: _titleCtrl,
                      enabled: !_submitting,
                      decoration: const InputDecoration(
                        labelText: 'Title',
                        hintText: 'e.g. Light Vehicle Licence',
                      ),
                      validator: (v) => (v == null || v.trim().length < 2)
                          ? 'Title is required'
                          : null,
                    ),
                    const Gap(10),
                    TextFormField(
                      controller: _issuerCtrl,
                      enabled: !_submitting,
                      decoration: const InputDecoration(
                        labelText: 'Issuer (optional)',
                        hintText: 'e.g. Department of Motor Traffic',
                      ),
                    ),
                    const Gap(10),
                    TextFormField(
                      controller: _credCtrl,
                      enabled: !_submitting,
                      decoration: const InputDecoration(
                        labelText: 'Credential / licence no. (optional)',
                      ),
                    ),
                    const Gap(18),
                    Text('Document', style: AppTextStyles.labelLarge),
                    const Gap(8),
                    if (_previewBytes != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(
                          _previewBytes!,
                          height: 140,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      ),
                    if (_previewBytes != null) const Gap(10),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: _docPath != null
                              ? AppColors.successColor
                              : AppColors.borderColor,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        color: ZivoPalette.of(context).surface,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                _docPath != null
                                    ? Icons.check_circle
                                    : Icons.upload_file_outlined,
                                color: _docPath != null
                                    ? AppColors.successColor
                                    : ZivoPalette.of(context).textMuted,
                              ),
                              const Gap(10),
                              Expanded(
                                child: Text(
                                  _docPath == null
                                      ? (_type.requiresDocument
                                          ? 'Document required — pick a clear photo'
                                          : 'Document optional')
                                      : (_docLabel ?? 'Document attached'),
                                  style: AppTextStyles.bodyMedium,
                                ),
                              ),
                              if (_docPath != null)
                                IconButton(
                                  tooltip: 'Remove',
                                  onPressed:
                                      _submitting ? null : _clearDocument,
                                  icon: const Icon(Icons.delete_outline,
                                      size: 20),
                                ),
                            ],
                          ),
                          const Gap(10),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: (_submitting || _picking)
                                  ? null
                                  : _pickDocument,
                              icon: _picking
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.photo_library_outlined,
                                      color: Colors.white, size: 18),
                              label: Text(
                                'Choose photo',
                                style: AppTextStyles.buttonLabel
                                    .copyWith(color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Sticky footer: Cancel + Submit
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _submitting ? null : widget.onClose,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          'Cancel',
                          style: AppTextStyles.buttonLabel.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                    const Gap(12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: _submitting ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
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
                            : Text(
                                'Submit for review',
                                style: AppTextStyles.buttonLabel
                                    .copyWith(color: Colors.white),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
