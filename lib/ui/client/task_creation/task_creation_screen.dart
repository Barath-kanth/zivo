import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hyperlocal/blocs/auth/auth_bloc.dart';
import 'package:hyperlocal/blocs/task/task_bloc.dart';
import 'package:hyperlocal/core/constants/app_colors.dart';
import 'package:hyperlocal/core/constants/app_config.dart';
import 'package:hyperlocal/core/constants/app_text_styles.dart';
import 'package:hyperlocal/core/router/app_router.dart';
import 'package:hyperlocal/core/services/policy/community_policy_engine.dart';
import 'package:hyperlocal/core/utils/auth_gate.dart';
import 'package:hyperlocal/data/models/task.dart';
import 'package:hyperlocal/data/models/task_status.dart';
import 'package:hyperlocal/data/repositories/profile_repository.dart';
import 'package:hyperlocal/data/repositories/task_repository.dart';
import 'package:hyperlocal/blocs/mode/mode_cubit.dart';
import 'package:image_picker/image_picker.dart';

/// Task creation — Uber-style category-first flow.
/// Step 0: Pick category  →  Step 1: Describe  →  Step 2: Location  →  Step 3: Review & Post
class TaskCreationScreen extends StatefulWidget {
  const TaskCreationScreen({super.key, this.initialCategory});

  /// When set (e.g. tapped from home grid), skip the category picker.
  final TaskCategory? initialCategory;

  @override
  State<TaskCreationScreen> createState() => _TaskCreationScreenState();
}

class _TaskCreationScreenState extends State<TaskCreationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _locationLabelCtrl = TextEditingController();

  TaskCategory? _selectedCategory;
  double _estimatedHours = 1.0;
  double _hourlyRate = 700.0; // derived from fair labor / hours
  double _goodsBudget = 0;
  int _clientBoostLkr = 0;
  String _urgency = 'normal';
  Map<String, dynamic>? _priceQuote;
  bool _quoting = false;
  String? _quoteError;
  final _boostCtrl = TextEditingController();
  final List<TextEditingController> _itemNameCtrls = [];
  final List<TextEditingController> _itemQtyCtrls = [];
  LatLng? _pickedLocation;
  int _step = 0;
  String? _livePolicyWarning;
  final _picker = ImagePicker();
  final List<Uint8List> _photoBytes = [];
  static const _maxPhotos = 5;
  /// Background safety only — never shown as a technical panel.
  bool _safetyBlocked = false;
  String? _safetyMessage;
  List<Map<String, dynamic>> _pricingFields = const [];
  final Map<String, dynamic> _fieldValues = {};
  final Map<String, TextEditingController> _fieldCtrls = {};
  bool _fieldsLoading = false;
  String _fieldsHeadline = 'A few details for a fair price';
  String _fieldsNote = '';

  // Sri Lankan cities
  static const _cityPresets = [
    ('Colombo',      6.9271,  79.8612),
    ('Kandy',        7.2906,  80.6337),
    ('Galle',        6.0535,  80.2210),
    ('Negombo',      7.2090,  79.8384),
    ('Jaffna',       9.6615,  80.0255),
    ('Matara',       5.9485,  80.5353),
    ('Kurunegala',   7.4863,  80.3647),
    ('Ratnapura',    6.6828,  80.3992),
    ('Anuradhapura', 8.3114,  80.4037),
    ('Trincomalee',  8.5874,  81.2152),
  ];

  Color _colorFor(TaskCategory cat) {
    switch (cat) {
      case TaskCategory.queueStanding:     return AppColors.catQueue;
      case TaskCategory.laundry:           return AppColors.catLaundry;
      case TaskCategory.groceryRun:        return AppColors.catGrocery;
      case TaskCategory.homeCleaning:      return AppColors.catCleaning;
      case TaskCategory.homeCooking:       return AppColors.catCooking;
      case TaskCategory.movingHelp:        return AppColors.catMoving;
      case TaskCategory.tutoring:          return AppColors.catTutoring;
      case TaskCategory.techHelp:          return AppColors.catTech;
      case TaskCategory.petCare:           return AppColors.catPetCare;
      case TaskCategory.tailoring:         return AppColors.catTailoring;
      case TaskCategory.driver:            return AppColors.catDriver;
      case TaskCategory.errandRun:         return AppColors.catErrand;
      case TaskCategory.gardening:         return AppColors.catGarden;
      case TaskCategory.documentWork:      return AppColors.catDocument;
      case TaskCategory.hospitalCompanion: return AppColors.catHospital;
      case TaskCategory.babysitting:       return AppColors.catBabysit;
      case TaskCategory.elderCare:         return AppColors.catElderCare;
      case TaskCategory.eventHelp:         return AppColors.catEvent;
      case TaskCategory.photography:       return AppColors.catPhoto;
      case TaskCategory.homeRepair:        return AppColors.catRepair;
      case TaskCategory.other:             return AppColors.textMuted;
    }
  }

  Color get _catColor =>
      _selectedCategory == null ? AppColors.accent : _colorFor(_selectedCategory!);

  @override
  void initState() {
    super.initState();
    _titleCtrl.addListener(_recheckPolicy);
    _descCtrl.addListener(_recheckPolicy);
    final initial = widget.initialCategory;
    if (initial != null) {
      _selectedCategory = initial;
      _step = 1;
      if (initial == TaskCategory.groceryRun ||
          initial == TaskCategory.errandRun) {
        _goodsBudget = 3000;
        _addShoppingItem();
      }
    }
  }

  void _recheckPolicy() {
    final result = CommunityPolicyEngine.evaluate(
      title: _titleCtrl.text,
      description: _descCtrl.text,
    );
    final warning = result.allowed ? null : result.userMessage;
    if (warning != _livePolicyWarning) {
      setState(() => _livePolicyWarning = warning);
    }
  }

  @override
  void dispose() {
    _titleCtrl.removeListener(_recheckPolicy);
    _descCtrl.removeListener(_recheckPolicy);
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _locationLabelCtrl.dispose();
    _boostCtrl.dispose();
    for (final c in _itemNameCtrls) {
      c.dispose();
    }
    for (final c in _itemQtyCtrls) {
      c.dispose();
    }
    for (final c in _fieldCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic> _collectContextFields() {
    final out = <String, dynamic>{};
    for (final f in _pricingFields) {
      final id = f['id']?.toString();
      if (id == null) continue;
      final type = f['type']?.toString() ?? 'text';
      if (type == 'boolean') {
        out[id] = _fieldValues[id] == true;
      } else if (type == 'number') {
        final raw = _fieldCtrls[id]?.text.trim() ?? '${_fieldValues[id] ?? ''}';
        out[id] = num.tryParse(raw) ?? raw;
      } else if (type == 'date') {
        final v = _fieldValues[id];
        if (v is DateTime) {
          out[id] = v.toUtc().toIso8601String();
        } else if (v != null) {
          out[id] = v.toString();
        }
      } else if (type == 'select') {
        out[id] = _fieldValues[id] ?? _fieldCtrls[id]?.text;
      } else {
        out[id] = _fieldCtrls[id]?.text.trim() ?? _fieldValues[id];
      }
    }
    out.removeWhere((k, v) => v == null || (v is String && v.isEmpty));
    return out;
  }

  String? _deadlineIso() {
    final ctx = _collectContextFields();
    final d = ctx['deadline_at'];
    if (d is String && d.isNotEmpty) return d;
    return DateTime.now().add(const Duration(hours: 24)).toUtc().toIso8601String();
  }

  Future<void> _loadPricingFields() async {
    final desc = _descCtrl.text.trim();
    if (desc.length < 20 || _selectedCategory == null) return;
    setState(() => _fieldsLoading = true);
    try {
      final res = await context.read<TaskRepository>().pricingFields(
            title: _titleCtrl.text.trim(),
            description: desc,
            category: _selectedCategory!.name,
          );
      if (!mounted) return;
      final fields = ((res['fields'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      for (final c in _fieldCtrls.values) {
        c.dispose();
      }
      _fieldCtrls.clear();
      _fieldValues.clear();
      for (final f in fields) {
        final id = f['id']?.toString();
        if (id == null) continue;
        final type = f['type']?.toString() ?? 'text';
        final def = f['default_value'];
        if (type == 'boolean') {
          _fieldValues[id] = def == true || def == 'true';
        } else if (type == 'date') {
          _fieldValues[id] =
              DateTime.now().add(const Duration(hours: 24));
        } else if (type == 'select') {
          _fieldValues[id] = def?.toString() ??
              ((f['options'] as List?)?.first?.toString() ?? '');
        } else {
          _fieldCtrls[id] = TextEditingController(
            text: def == null ? '' : '$def',
          );
        }
      }
      setState(() {
        _pricingFields = fields;
        _fieldsHeadline =
            res['headline']?.toString() ?? 'A few details for a fair price';
        _fieldsNote = res['note']?.toString() ?? '';
        _fieldsLoading = false;
      });
      await _refreshFairQuote();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _fieldsLoading = false;
        _quoteError = '$e';
      });
    }
  }

  Future<void> _refreshFairQuote() async {
    final desc = _descCtrl.text.trim();
    final loc = _pickedLocation;
    if (desc.length < 20 || loc == null || _selectedCategory == null) {
      setState(() {
        _quoteError = desc.length < 20
            ? 'Description must be at least 20 characters'
            : 'Pick a location first';
        _priceQuote = null;
      });
      return;
    }
    setState(() {
      _quoting = true;
      _quoteError = null;
    });
    try {
      final ctx = _collectContextFields();
      final q = await context.read<TaskRepository>().priceQuote(
            title: _titleCtrl.text.trim(),
            description: desc,
            category: _selectedCategory!.name,
            lat: loc.latitude,
            lon: loc.longitude,
            urgency: _urgency,
            deadlineAt: _deadlineIso(),
            clientBoostLkr: _clientBoostLkr,
            contextFields: ctx,
          );
      if (!mounted) return;
      final labor = (q['labor_lkr'] as num?)?.toDouble();
      final hours = (q['duration_hours'] as num?)?.toDouble() ?? _estimatedHours;
      setState(() {
        _priceQuote = q;
        _quoting = false;
        _estimatedHours = hours;
        if (labor != null && hours > 0) {
          _hourlyRate = labor / hours;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _quoting = false;
        _quoteError = '$e';
        _priceQuote = null;
      });
    }
  }

  Future<void> _runSafetyInBackground() async {
    try {
      final safety = await context.read<TaskRepository>().safetyCheck(
            title: _titleCtrl.text.trim().isEmpty
                ? '(no title)'
                : _titleCtrl.text.trim(),
            description: _descCtrl.text.trim(),
          );
      if (!mounted) return;
      final allowed = safety['allowed'] != false;
      setState(() {
        _safetyBlocked = !allowed;
        _safetyMessage = allowed
            ? null
            : (safety['reasoning']?.toString() ??
                'This request doesn’t meet community guidelines');
      });
    } catch (_) {
      /* don’t block UX on background check failure */
    }
  }

  bool get _needsPurchaseTrust =>
      _selectedCategory == TaskCategory.groceryRun ||
      _selectedCategory == TaskCategory.errandRun;

  void _addShoppingItem() {
    setState(() {
      _itemNameCtrls.add(TextEditingController());
      _itemQtyCtrls.add(TextEditingController(text: '1'));
    });
  }

  String _shoppingListBlock() {
    final lines = <String>[];
    for (var i = 0; i < _itemNameCtrls.length; i++) {
      final name = _itemNameCtrls[i].text.trim();
      if (name.isEmpty) continue;
      final qty = i < _itemQtyCtrls.length
          ? _itemQtyCtrls[i].text.trim()
          : '1';
      lines.add('- $name × ${qty.isEmpty ? '1' : qty}');
    }
    if (lines.isEmpty) return '';
    return '\n\nSHOPPING LIST (do not give cash to helper):\n${lines.join('\n')}';
  }

  /// Reset everything back to step 0, clearing all form state.
  void _resetToStart() {
    setState(() {
      _step = 0;
      _selectedCategory = null;
      _titleCtrl.clear();
      _descCtrl.clear();
      _locationLabelCtrl.clear();
      _pickedLocation = null;
      _estimatedHours = 1.0;
      _hourlyRate = 700.0;
      _clientBoostLkr = 0;
      _urgency = 'normal';
      _priceQuote = null;
      _quoteError = null;
      _boostCtrl.clear();
      _livePolicyWarning = null;
      _photoBytes.clear();
      _safetyBlocked = false;
      _safetyMessage = null;
      _pricingFields = const [];
      _fieldsHeadline = 'A few details for a fair price';
      _fieldsNote = '';
      for (final c in _fieldCtrls.values) {
        c.dispose();
      }
      _fieldCtrls.clear();
      _fieldValues.clear();
    });
  }

  Future<void> _addPhotos() async {
    if (_photoBytes.length >= _maxPhotos) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('You can add up to $_maxPhotos photos')),
      );
      return;
    }
    try {
      final remaining = _maxPhotos - _photoBytes.length;
      final files = await _picker.pickMultiImage(
        imageQuality: 75,
        maxWidth: 1600,
      );
      if (files.isEmpty) return;
      final selected = files.take(remaining);
      final bytes = <Uint8List>[];
      for (final f in selected) {
        bytes.add(await f.readAsBytes());
      }
      if (!mounted) return;
      setState(() => _photoBytes.addAll(bytes));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not add photos: $e')),
      );
    }
  }

  Future<void> _addPhotoFromCamera() async {
    if (_photoBytes.length >= _maxPhotos) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('You can add up to $_maxPhotos photos')),
      );
      return;
    }
    try {
      final file = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 75,
        maxWidth: 1600,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() => _photoBytes.add(bytes));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not take photo: $e')),
      );
    }
  }

  void _removePhoto(int index) {
    setState(() => _photoBytes.removeAt(index));
  }

  void _goBack() {
    if (_step == 0) {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/');
      }
    } else if (_step == 1) {
      // Going back from describe → reset to category picker & clear form
      _resetToStart();
    } else {
      setState(() => _step--);
    }
  }

  Widget _buildMiniModeToggle() {
    return BlocBuilder<ModeCubit, ModeState>(
      builder: (context, state) {
        final isHelper = state is HelperMode;
        final isToggling = state is ModeToggling;
        
        return GestureDetector(
          onTap: isToggling ? null : () {
            context.read<ModeCubit>().toggleMode();
            context.go('/');
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isHelper ? AppColors.helperAccent.withOpacity(0.1) : AppColors.accent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isHelper ? AppColors.helperAccent : AppColors.accent,
                width: 1.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isHelper ? Icons.handshake_rounded : Icons.person_search_rounded,
                  color: isHelper ? AppColors.helperAccent : AppColors.accent,
                  size: 14,
                ),
                const Gap(4),
                Text(
                  isHelper ? 'HELP' : 'HIRE',
                  style: TextStyle(
                    color: isHelper ? AppColors.helperAccent : AppColors.accent,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _submit() async {
    if (_pickedLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select your city')),
      );
      return;
    }
    if (!await requireAuth(context, returnTo: AppRoutes.createTask)) return;
    if (!mounted) return;
    if (!await requireVerified(context, returnTo: AppRoutes.createTask)) return;
    if (!mounted) return;
    final auth = context.read<AuthBloc>().state;
    if (auth is! AuthAuthenticated) return;

    final policy = CommunityPolicyEngine.evaluate(
      title: _titleCtrl.text,
      description: _descCtrl.text,
    );
    if (!policy.allowed) {
      context.read<ProfileRepository>().logPolicyViolation(
            matchedRule: policy.matchedRule ?? 'unknown',
            snippet: '${_titleCtrl.text} ${_descCtrl.text}',
          );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            policy.userMessage ??
                'This task violates Hyperlocal community guidelines.',
            style: const TextStyle(color: Colors.white),
          ),
          backgroundColor: AppColors.errorColor,
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }

    // Community safety (background tech — user-facing copy only).
    try {
      final safety = await context.read<TaskRepository>().safetyCheck(
            title: _titleCtrl.text,
            description: _descCtrl.text,
          );
      if (safety['allowed'] != true) {
        final reasoning = safety['reasoning']?.toString() ??
            (safety['reasons'] as List?)?.join(' · ') ??
            'This request doesn’t meet community guidelines';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              reasoning,
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor: AppColors.errorColor,
            duration: const Duration(seconds: 6),
          ),
        );
        return;
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Safety check unavailable: $e'),
          backgroundColor: AppColors.warningColor,
        ),
      );
      return;
    }

    // Verified KYC required for every post (server also enforces).
    if (!auth.profile.isKycVerified) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Verify your identity before posting. Admin must approve your documents.',
          ),
          backgroundColor: AppColors.errorColor,
        ),
      );
      return;
    }

    if (_needsPurchaseTrust) {
      if (_goodsBudget < 100) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Set a goods budget (min ${AppConfig.money(100)}) held in escrow. '
              'Never give cash to the helper.',
            ),
            backgroundColor: AppColors.errorColor,
          ),
        );
        return;
      }
      final hasItem = _itemNameCtrls.any((c) => c.text.trim().isNotEmpty);
      if (!hasItem) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Add at least one shopping-list item.'),
            backgroundColor: AppColors.errorColor,
          ),
        );
        return;
      }
    }

    final description =
        '${_descCtrl.text.trim()}${_shoppingListBlock()}';

    // Upload reference photos (any category) before create.
    final photoUrls = <String>[];
    final photoPaths = <String>[];
    if (_photoBytes.isNotEmpty) {
      try {
        final repo = context.read<TaskRepository>();
        for (var i = 0; i < _photoBytes.length; i++) {
          final uploaded = await repo.uploadTaskPhoto(
            bytes: _photoBytes[i],
            filename: 'task_${DateTime.now().millisecondsSinceEpoch}_$i.jpg',
          );
          photoUrls.add(uploaded['url']!);
          final path = uploaded['path'];
          if (path != null && path.isNotEmpty) photoPaths.add(path);
        }
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Photo upload failed: $e'),
            backgroundColor: AppColors.errorColor,
          ),
        );
        return;
      }
    }

    final labor = (_priceQuote?['labor_lkr'] as num?)?.toDouble() ??
        (_estimatedHours * _hourlyRate);
    final task = Task(
      id: '',
      clientId: auth.profile.id,
      title: _titleCtrl.text.trim(),
      description: description,
      category: _selectedCategory!,
      estimatedHours: _estimatedHours,
      hourlyRate: _hourlyRate,
      totalAmount: labor,
      location: _pickedLocation!,
      locationAddress: _locationLabelCtrl.text.trim().isEmpty
          ? null
          : _locationLabelCtrl.text.trim(),
      locationLabel: _locationLabelCtrl.text.trim().isEmpty
          ? null
          : _locationLabelCtrl.text.trim(),
      status: TaskStatus.open,
      createdAt: DateTime.now(),
      goodsBudget: _needsPurchaseTrust ? _goodsBudget : 0,
      requiresPurchaseProof: _needsPurchaseTrust,
      photoUrls: photoUrls,
      photoPaths: photoPaths,
    );
    if (!mounted) return;
    final ctx = _collectContextFields();
    context.read<TaskBloc>().add(TaskCreate(
          task,
          deadlineAt: _deadlineIso(),
          clientBoostLkr: _clientBoostLkr,
          urgency: _urgency,
          contextFields: ctx,
        ));
  }

  @override
  Widget build(BuildContext context) {
    final stepLabels = [
      'Choose Category',
      'Describe Task',
      'Set Location',
      'Review & Post',
    ];

    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundDark,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            _step == 0 ? Icons.close_rounded : Icons.arrow_back_ios_new_rounded,
            color: AppColors.textSecondary,
            size: 20,
          ),
          onPressed: _goBack,
        ),
        title: Text(stepLabels[_step], style: AppTextStyles.headingSmall),
        centerTitle: true,
        actions: _step == 0 ? [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: _buildMiniModeToggle(),
          ),
        ] : null,
      ),
      body: BlocListener<TaskBloc, TaskState>(
        listener: (context, state) {
          if (state is TaskCreated) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('✅ Task posted! You\'ll be matched shortly.'),
                backgroundColor: Color(0xFF2E7D32),
              ),
            );
            context.go('/');
          }
          if (state is TaskFailure) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: AppColors.errorColor,
              ),
            );
          }
        },
        child: Column(
          children: [
            _buildProgressBar(),
            Expanded(
              child: switch (_step) {
                0 => _buildStep0Category(),
                1 => _buildStep1Describe(),
                2 => _buildStep2Location(),
                _ => _buildStep3Pricing(),
              },
            ),
            if (_step > 0 && _step < 3) _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  // ── Progress bar ──────────────────────────────────────────────────────────

  Widget _buildProgressBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Row(
        children: List.generate(4, (i) {
          final done = i <= _step;
          return Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              height: 3,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: done ? _catColor : AppColors.borderColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }),
      ),
    );
  }

  // ── Step 0: Category picker ───────────────────────────────────────────────

  Widget _buildStep0Category() {
    final cats = TaskCategory.values;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'What kind of help\ndo you need?',
                  style: AppTextStyles.displayMedium.copyWith(fontSize: 22),
                ).animate().fadeIn(duration: 300.ms).slideY(begin: -0.05),
                const Gap(4),
                Text(
                  'Tap a category to get started',
                  style: AppTextStyles.bodyMedium,
                ).animate().fadeIn(delay: 100.ms),
              ],
            ),
          ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 140,
              childAspectRatio: 1.25,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: cats.length,
            itemBuilder: (ctx, i) {
              final cat = cats[i];
              return GestureDetector(
                onTap: () {
                  setState(() => _selectedCategory = cat);
                  Future.delayed(const Duration(milliseconds: 180),
                      () { if (mounted) setState(() => _step = 1); });
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.cardDark,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        cat.emoji,
                        style: const TextStyle(fontSize: 28),
                      ),
                      const Gap(6),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: Text(
                          cat.displayName,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            height: 1.2,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                        ),
                      ),
                    ],
                  ),
                )
                    .animate(delay: Duration(milliseconds: 20 * i))
                    .fadeIn(duration: 220.ms)
                    .scale(begin: const Offset(0.88, 0.88)),
              );
            },
          ),
        ],
      ),
    );
  }

  // ── Step 1: Describe ──────────────────────────────────────────────────────

  Widget _buildStep1Describe() {
    if (_selectedCategory == null) return const SizedBox.shrink();
    final color = _catColor;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Category banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: color.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.18),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        _selectedCategory!.emoji,
                        style: const TextStyle(fontSize: 20),
                      ),
                    ),
                  ),
                  const Gap(12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _selectedCategory!.displayName,
                          style: AppTextStyles.headingSmall
                              .copyWith(color: color, fontSize: 13),
                        ),
                        const Gap(2),
                        Text(
                          _selectedCategory!.description,
                          style: AppTextStyles.bodySmall
                              .copyWith(fontSize: 11),
                          maxLines: 2,
                        ),
                      ],
                    ),
                  ),
                  // Change category button
                  GestureDetector(
                    onTap: _resetToStart,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.cardElevated,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.borderColor),
                      ),
                      child: Text(
                        'Change',
                        style: AppTextStyles.bodySmall.copyWith(
                            fontSize: 10,
                            color: AppColors.textMuted),
                      ),
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn(duration: 280.ms),

            const Gap(22),
            _FieldLabel('Task Title'),
            const Gap(8),
            TextFormField(
              controller: _titleCtrl,
              style: AppTextStyles.bodyLarge,
              decoration: InputDecoration(
                hintText:
                    'e.g. ${_selectedCategory!.description.split(' ').take(6).join(' ')}…',
                hintStyle: AppTextStyles.bodyLarge
                    .copyWith(color: AppColors.textMuted),
                prefixIcon: Icon(Icons.title_rounded,
                    color: AppColors.textMuted, size: 18),
              ),
              validator: (v) =>
                  (v?.trim().isEmpty ?? true) ? 'Please add a title' : null,
            ),

            const Gap(18),
            _FieldLabel('More Details (required · min 20 chars)'),
            const Gap(8),
            TextFormField(
              controller: _descCtrl,
              maxLines: 5,
              style: AppTextStyles.bodyLarge,
              decoration: InputDecoration(
                hintText:
                    'Describe the full job — what to do, where, any delivery, size, timing…',
                alignLabelWithHint: true,
                helperText:
                    'Next we’ll ask only the details needed to price this task',
                prefixIcon: const Padding(
                  padding: EdgeInsets.only(bottom: 60),
                  child: Icon(Icons.notes_rounded,
                      color: AppColors.textMuted, size: 18),
                ),
              ),
              validator: (v) {
                final t = v?.trim() ?? '';
                if (t.isEmpty) return 'Please add details';
                if (t.length < 20) return 'At least 20 characters required';
                return null;
              },
            ),

            const Gap(18),
            _FieldLabel('Photos (optional · all categories)'),
            const Gap(8),
            Text(
              'Add up to $_maxPhotos photos so helpers see the place, items, or context.',
              style: AppTextStyles.bodySmall
                  .copyWith(color: AppColors.textMuted, fontSize: 11),
            ),
            const Gap(10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                ...List.generate(_photoBytes.length, (i) {
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(
                          _photoBytes[i],
                          width: 88,
                          height: 88,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        top: -6,
                        right: -6,
                        child: InkWell(
                          onTap: () => _removePhoto(i),
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: const BoxDecoration(
                              color: AppColors.errorColor,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.close, size: 14, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  );
                }),
                if (_photoBytes.length < _maxPhotos)
                  OutlinedButton(
                    onPressed: _addPhotos,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(88, 88),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      side: BorderSide(color: color.withValues(alpha: 0.45)),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_photo_alternate_outlined,
                            color: color, size: 22),
                        const Gap(4),
                        Text(
                          'Gallery',
                          style: AppTextStyles.bodySmall
                              .copyWith(color: color, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                if (_photoBytes.length < _maxPhotos)
                  OutlinedButton(
                    onPressed: _addPhotoFromCamera,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(88, 88),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      side: BorderSide(color: color.withValues(alpha: 0.45)),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.photo_camera_outlined,
                            color: color, size: 22),
                        const Gap(4),
                        Text(
                          'Camera',
                          style: AppTextStyles.bodySmall
                              .copyWith(color: color, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
              ],
            ),

            if (_livePolicyWarning != null) ...[
              const Gap(14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.errorColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.errorColor.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.gavel_rounded,
                        color: AppColors.errorColor, size: 18),
                    const Gap(10),
                    Expanded(
                      child: Text(
                        _livePolicyWarning!,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.errorColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            if (_safetyBlocked && _safetyMessage != null) ...[
              const Gap(16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.errorColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.errorColor.withValues(alpha: 0.35),
                  ),
                ),
                child: Text(
                  _safetyMessage!,
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.errorColor),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Step 2: Location ──────────────────────────────────────────────────────

  Widget _buildStep2Location() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Where do you need help?',
              style: AppTextStyles.displayMedium.copyWith(fontSize: 20))
              .animate().fadeIn(duration: 280.ms),
          const Gap(4),
          Text('Pick your city, then add the exact address.',
              style: AppTextStyles.bodyMedium),
          const Gap(18),

          // Category grid
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 140,
              childAspectRatio: 1.25,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: _cityPresets.length,
            itemBuilder: (ctx, i) {
              final (name, lat, lng) = _cityPresets[i];
              final isSelected = _pickedLocation?.latitude == lat &&
                  _pickedLocation?.longitude == lng;
              return GestureDetector(
                onTap: () => setState(() {
                  _pickedLocation = LatLng(lat, lng);
                  if (_locationLabelCtrl.text.isEmpty) {
                    _locationLabelCtrl.text = name;
                  }
                }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? _catColor.withValues(alpha: 0.14)
                        : AppColors.cardDark,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected ? _catColor : AppColors.borderColor,
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isSelected
                            ? Icons.check_circle_rounded
                            : Icons.location_on_outlined,
                        color: isSelected ? _catColor : AppColors.textMuted,
                        size: 15,
                      ),
                      const Gap(8),
                      Expanded(
                        child: Text(
                          name,
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: isSelected
                                ? _catColor
                                : AppColors.textSecondary,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.w400,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),

          const Gap(18),
          _FieldLabel('Exact Address / Landmark'),
          const Gap(8),
          TextFormField(
            controller: _locationLabelCtrl,
            style: AppTextStyles.bodyLarge,
            decoration: const InputDecoration(
              hintText: 'e.g. Near Commercial Bank, Galle Road',
              prefixIcon: Icon(Icons.home_outlined,
                  color: AppColors.textMuted, size: 18),
            ),
          ),

          if (_pickedLocation != null) ...[
            const Gap(12),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF1B5E20).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: const Color(0xFF388E3C).withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline_rounded,
                      color: Color(0xFF66BB6A), size: 15),
                  const Gap(8),
                  Text('Location pinned ✔',
                      style: AppTextStyles.bodySmall.copyWith(
                          color: const Color(0xFF66BB6A))),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Step 3: Pricing & review ──────────────────────────────────────────────

  Widget _buildDynamicField(Map<String, dynamic> f) {
    final id = f['id']?.toString() ?? '';
    final label = f['label']?.toString() ?? id;
    final type = f['type']?.toString() ?? 'text';
    final unit = f['unit']?.toString();
    final help = f['help']?.toString();
    final required = f['required'] == true;

    if (type == 'boolean') {
      return SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: Text(label, style: AppTextStyles.bodyMedium),
        subtitle: help != null
            ? Text(help, style: AppTextStyles.bodySmall)
            : null,
        value: _fieldValues[id] == true,
        onChanged: (v) {
          setState(() => _fieldValues[id] = v);
          _refreshFairQuote();
        },
      );
    }

    if (type == 'select') {
      final options =
          ((f['options'] as List?) ?? const []).map((e) => '$e').toList();
      final current = _fieldValues[id]?.toString() ??
          (options.isNotEmpty ? options.first : '');
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FieldLabel(required ? '$label *' : label),
          const Gap(6),
          Wrap(
            spacing: 6,
            children: [
              for (final o in options)
                ChoiceChip(
                  label: Text(o),
                  selected: current == o,
                  onSelected: (_) {
                    setState(() => _fieldValues[id] = o);
                    _refreshFairQuote();
                  },
                ),
            ],
          ),
        ],
      );
    }

    if (type == 'date') {
      final dt = _fieldValues[id] is DateTime
          ? _fieldValues[id] as DateTime
          : DateTime.now().add(const Duration(hours: 24));
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FieldLabel(required ? '$label *' : label),
          const Gap(6),
          OutlinedButton.icon(
            onPressed: () async {
              final date = await showDatePicker(
                context: context,
                initialDate: dt,
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 60)),
              );
              if (date == null || !mounted) return;
              final time = await showTimePicker(
                context: context,
                initialTime: TimeOfDay.fromDateTime(dt),
              );
              if (time == null || !mounted) return;
              setState(() {
                _fieldValues[id] = DateTime(
                  date.year,
                  date.month,
                  date.day,
                  time.hour,
                  time.minute,
                );
              });
              _refreshFairQuote();
            },
            icon: const Icon(Icons.event_rounded, size: 18),
            label: Text(
              '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
              '${dt.day.toString().padLeft(2, '0')} '
              '${dt.hour.toString().padLeft(2, '0')}:'
              '${dt.minute.toString().padLeft(2, '0')}',
            ),
          ),
        ],
      );
    }

    _fieldCtrls.putIfAbsent(id, () => TextEditingController());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(required ? '$label *' : label),
        const Gap(6),
        TextField(
          controller: _fieldCtrls[id],
          keyboardType: type == 'number'
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
          decoration: InputDecoration(
            hintText: help,
            suffixText: unit,
          ),
          onChanged: (_) {},
          onEditingComplete: _refreshFairQuote,
        ),
      ],
    );
  }

  Widget _buildStep3Pricing() {
    if (_selectedCategory == null) return const SizedBox.shrink();
    final floor = (_priceQuote?['gemini_labor_lkr'] as num?)?.toDouble();
    final total = (_priceQuote?['labor_lkr'] as num?)?.toDouble() ??
        (_estimatedHours * _hourlyRate);
    final helperEarns = total * 0.9;
    final escrowAll = total + (_needsPurchaseTrust ? _goodsBudget : 0);
    final color = _catColor;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _fieldsHeadline,
            style: AppTextStyles.displayMedium.copyWith(fontSize: 20),
          ).animate().fadeIn(duration: 280.ms),
          const Gap(4),
          Text(
            _fieldsNote.isEmpty
                ? 'Answer what’s relevant for this job. You can accept the fair price or add a tip — not lower it.'
                : _fieldsNote,
            style: AppTextStyles.bodyMedium,
          ),
          const Gap(20),

          if (_fieldsLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else ...[
            for (final f in _pricingFields) ...[
              _buildDynamicField(f),
              const Gap(14),
            ],
          ],

          _FieldLabel('Optional tip for the helper'),
          const Gap(6),
          TextField(
            controller: _boostCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              hintText: '0 = accept fair price',
              prefixText: 'LKR ',
            ),
            onChanged: (v) {
              _clientBoostLkr = int.tryParse(v.trim()) ?? 0;
              if (_clientBoostLkr < 0) _clientBoostLkr = 0;
            },
            onEditingComplete: _refreshFairQuote,
          ),
          const Gap(10),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: (_quoting || _fieldsLoading) ? null : _refreshFairQuote,
              icon: _quoting
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded, size: 18),
              label: Text(_quoting ? 'Updating price…' : 'Update fair price'),
            ),
          ),

          if (_quoteError != null) ...[
            const Gap(8),
            Text(_quoteError!,
                style: AppTextStyles.bodySmall
                    .copyWith(color: AppColors.errorColor)),
          ],

          const Gap(14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.accent.withValues(alpha: 0.25),
              ),
            ),
            child: _quoting
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _priceQuote == null
                            ? 'Fill the details above to see your fair price'
                            : 'Pay LKR ${total.toStringAsFixed(0)}',
                        style: AppTextStyles.headingSmall.copyWith(fontSize: 16),
                      ),
                      if (floor != null) ...[
                        const Gap(4),
                        Text(
                          'Fair floor LKR ${floor.toStringAsFixed(0)}'
                          '${_clientBoostLkr > 0 ? ' + tip $_clientBoostLkr' : ''}'
                          ' · helpers are protected from undercuts',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.textMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                      if (_priceQuote?['explanation'] != null) ...[
                        const Gap(6),
                        Text(
                          '${_priceQuote!['explanation']}',
                          style: AppTextStyles.bodySmall.copyWith(fontSize: 11),
                        ),
                      ],
                    ],
                  ),
          ),

          if (_needsPurchaseTrust) ...[
            const Gap(22),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.errorColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.errorColor.withValues(alpha: 0.35),
                ),
              ),
              child: Text(
                'ZERO CASH RULE: Do not give cash to the helper. '
                'Escrow a goods budget below. Helper pays at the till, uploads '
                'receipt + bag photos, then is reimbursed from escrow (capped). '
                'Seller vs helper disputes use the receipt evidence.',
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textPrimary,
                  height: 1.4,
                ),
              ),
            ),
            const Gap(16),
            _FieldLabel('Goods budget (${AppConfig.currencyCode})'),
            const Gap(6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  AppConfig.money(_goodsBudget),
                  style: AppTextStyles.headingSmall
                      .copyWith(color: AppColors.helperAccent),
                ),
                Text('Held in escrow', style: AppTextStyles.bodySmall),
              ],
            ),
            Slider(
              value: _goodsBudget.clamp(0, 25000),
              min: 0,
              max: 25000,
              divisions: 50,
              activeColor: AppColors.helperAccent,
              inactiveColor: AppColors.borderColor,
              onChanged: (v) => setState(() => _goodsBudget = v),
            ),
            const Gap(12),
            Row(
              children: [
                Text('Shopping list', style: AppTextStyles.labelLarge),
                const Spacer(),
                TextButton.icon(
                  onPressed: _addShoppingItem,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add item'),
                ),
              ],
            ),
            if (_itemNameCtrls.isEmpty)
              Text(
                'Add items the helper must buy (brand/size in notes if needed).',
                style: AppTextStyles.bodySmall,
              ),
            ...List.generate(_itemNameCtrls.length, (i) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _itemNameCtrls[i],
                        decoration: const InputDecoration(
                          hintText: 'Item name',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const Gap(8),
                    Expanded(
                      child: TextField(
                        controller: _itemQtyCtrls[i],
                        decoration: const InputDecoration(
                          hintText: 'Qty',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],

          const Gap(22),

          // Summary card
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.cardElevated,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: color.withValues(alpha: 0.22)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.14),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(_selectedCategory!.emoji,
                            style: const TextStyle(fontSize: 19)),
                      ),
                    ),
                    const Gap(10),
                    Text(_selectedCategory!.displayName,
                        style: AppTextStyles.headingSmall
                            .copyWith(color: color)),
                  ],
                ),
                const Divider(height: 22),
                ...() {
                  final ctx = _collectContextFields();
                  final rows = <Widget>[];
                  for (final f in _pricingFields) {
                    final id = f['id']?.toString();
                    if (id == null || !ctx.containsKey(id)) continue;
                    final label = f['label']?.toString() ?? id;
                    var val = ctx[id];
                    if (val is DateTime) {
                      val =
                          '${val.month}/${val.day} ${val.hour.toString().padLeft(2, '0')}:${val.minute.toString().padLeft(2, '0')}';
                    } else if (val is bool) {
                      val = val ? 'Yes' : 'No';
                    }
                    final unit = f['unit']?.toString();
                    rows.add(_ReviewRow(
                      label,
                      unit != null && unit.isNotEmpty ? '$val $unit' : '$val',
                    ));
                    if (rows.length >= 6) break;
                  }
                  if (rows.isEmpty) {
                    rows.add(_ReviewRow(
                      'Est. time',
                      '${_estimatedHours.toStringAsFixed(1)} hr',
                    ));
                  }
                  return rows;
                }(),
                const Divider(height: 18),
                _ReviewRow('Labor', AppConfig.money(total), bold: true),
                if (_needsPurchaseTrust)
                  _ReviewRow('Goods budget', AppConfig.money(_goodsBudget)),
                if (_needsPurchaseTrust)
                  _ReviewRow('Total escrow', AppConfig.money(escrowAll),
                      bold: true, color: AppColors.helperAccent),
                _ReviewRow('Helper labor (90%)',
                    AppConfig.money(helperEarns),
                    color: AppColors.helperAccent),
                _ReviewRow(
                  'Photos',
                  _photoBytes.isEmpty
                      ? 'None'
                      : '${_photoBytes.length} attached',
                ),
                const Gap(6),
                Text(
                  _needsPurchaseTrust
                      ? 'Goods reimbursed from escrow vs receipt. Never give cash to the helper.'
                      : '10% platform fee covers trust & secure escrow payment.',
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.textMuted),
                  textAlign: TextAlign.center,
                ),
                const Gap(18),
                BlocBuilder<TaskBloc, TaskState>(
                  builder: (context, state) {
                    final loading = state is TaskLoading;
                    return SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: loading || _quoting || _priceQuote == null
                            ? null
                            : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: color,
                          foregroundColor: Colors.white,
                          padding:
                              const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                        child: loading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white),
                              )
                            : Text(
                                'Post Task — LKR ${total.toStringAsFixed(2)}',
                                style: AppTextStyles.buttonLabel
                                    .copyWith(color: Colors.white, fontSize: 15),
                              ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Bottom navigation bar (steps 1 & 2) ───────────────────────────────────

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.borderColor)),
        color: AppColors.backgroundDark,
      ),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _onNext,
          style: ElevatedButton.styleFrom(
            backgroundColor: _catColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
            elevation: 0,
          ),
          child: Text(
            _step == 1
                ? 'Continue — Add Location'
                : 'Continue — Fair price',
            style: AppTextStyles.buttonLabel
                .copyWith(color: Colors.white, fontSize: 14),
          ),
        ),
      ),
    );
  }

  void _onNext() {
    if (_step == 1) {
      if (_formKey.currentState?.validate() ?? false) {
        _runSafetyInBackground();
        setState(() => _step = 2);
      }
    } else if (_step == 2) {
      if (_pickedLocation == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select your city first')),
        );
        return;
      }
      if (_safetyBlocked) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_safetyMessage ?? 'This request can’t be posted'),
            backgroundColor: AppColors.errorColor,
          ),
        );
        return;
      }
      setState(() => _step = 3);
      _loadPricingFields();
    }
  }
}

// ── Reusable widgets ──────────────────────────────────────────────────────────

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.label);
  final String label;
  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: AppTextStyles.labelLarge.copyWith(
        fontSize: 12,
        letterSpacing: 0.5,
      ),
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow(this.label, this.value, {this.bold = false, this.color});
  final String label;
  final String value;
  final bool bold;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: bold
                  ? AppTextStyles.headingSmall
                  : AppTextStyles.bodyMedium),
          Text(value,
              style: bold
                  ? AppTextStyles.headingSmall
                      .copyWith(color: color ?? AppColors.accent)
                  : AppTextStyles.bodyMedium.copyWith(color: color)),
        ],
      ),
    );
  }
}
