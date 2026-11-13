import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/router/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/network/app_error.dart';
import '../../../../core/utils/relative_time.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/list_skeleton.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/course_editor_providers.dart';
import '../../application/providers/lms_providers.dart';
import '../../infrastructure/data_sources/remote/course_editor_remote_ds.dart';
import '../components/lms_footer.dart';
import '../components/lms_header.dart';
import '../lms_course_actions.dart';
import '../lms_nav.dart';

/// Webapp `CourseEditorScreen` (Training › Course builder › New / Edit):
/// without an id the "New course" create step; with one the editor — modules
/// (add, rename, reorder, delete), lesson videos (TUS upload to Bunny,
/// encoding status, reorder, delete), PDF resources, a staged thumbnail and
/// the course settings, all saved to the server. Platform courses are
/// read-only and redirect to their detail page.
class LmsBuilderScreen extends ConsumerWidget {
  const LmsBuilderScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = GoRouterState.of(context).uri.queryParameters['id'] ?? '';
    if (id.isEmpty) return const _NewCoursePanel();
    final async = ref.watch(editorCourseProvider(id));
    final course = async.valueOrNull;
    if (course == null) {
      final e = async.error;
      return _Shell(
        title: 'Course editor',
        child: async.isLoading
            ? const DetailSkeleton()
            : Padding(
                padding: EdgeInsets.all(24.r),
                child: Text(
                  e is AppError && e.type != AppErrorType.notFound
                      ? e.message
                      : 'Course not found.',
                  style: AppText.custom(
                      size: 14,
                      weight: FontWeight.w500,
                      color: AppColors.textMuted),
                ),
              ),
      );
    }
    if (course.isGlobal) {
      // Webapp CourseEditorLoader: a tenant never edits a platform course.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted)
          context.pushReplacement('${Routes.lmsCourseDetail}?id=$id');
      });
      return const _Shell(title: 'Course editor', child: DetailSkeleton());
    }
    return _CourseEditorForm(key: ValueKey(id), initial: course);
  }
}

/// Header + body frame shared by the editor states.
class _Shell extends StatelessWidget {
  const _Shell({required this.title, required this.child, this.footer});
  final String title;
  final Widget child;
  final Widget? footer;

  @override
  Widget build(BuildContext context) => Container(
        color: AppColors.bgScreen,
        child: Column(
          children: [
            LmsHeader(
              onBack: () => lmsBack(context, fallback: Routes.lmsCourses),
              title: Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.custom(
                      size: 20,
                      weight: FontWeight.w800,
                      color: AppColors.textPrimary,
                      letterSpacing: -0.4)),
            ),
            Expanded(child: child),
            if (footer != null) footer!,
          ],
        ),
      );
}

// ── Shared bits ──

Widget _card({required Widget child, String? title, String? optional}) =>
    ClozrCard(
      radius: 16,
      padding: EdgeInsets.all(16.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Padding(
              padding: EdgeInsets.only(bottom: 10.h),
              child: Text.rich(TextSpan(
                text: title,
                style: AppText.custom(
                    size: 15,
                    weight: FontWeight.w700,
                    color: AppColors.textPrimary),
                children: [
                  if (optional != null)
                    TextSpan(
                        text: '  $optional',
                        style: AppText.custom(
                            size: 12,
                            weight: FontWeight.w500,
                            color: AppColors.textPlaceholder)),
                ],
              )),
            ),
          child,
        ],
      ),
    );

InputDecoration _inputDeco(String hint) => InputDecoration(
      hintText: hint,
      hintStyle: AppText.custom(
          size: 14, weight: FontWeight.w500, color: AppColors.textPlaceholder),
      isDense: true,
      contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
      filled: true,
      fillColor: AppColors.white,
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11.r),
          borderSide: const BorderSide(color: AppColors.borderInput)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11.r),
          borderSide: const BorderSide(color: AppColors.navy)),
    );

Widget _primaryButton(String label, VoidCallback? onTap, {IconData? icon}) =>
    GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 46.h,
        padding: EdgeInsets.symmetric(horizontal: 16.w),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: onTap == null ? AppColors.textPlaceholder : AppColors.navy,
          borderRadius: BorderRadius.circular(12.r),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 15.sp, color: AppColors.white),
              SizedBox(width: 6.w)
            ],
            Text(label,
                style: AppText.custom(
                    size: 14, weight: FontWeight.w700, color: AppColors.white)),
          ],
        ),
      ),
    );

Widget _outlineButton(String label, VoidCallback? onTap) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 46.h,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(color: AppColors.borderInput),
        ),
        child: Text(label,
            style: AppText.custom(
                size: 14,
                weight: FontWeight.w700,
                color: AppColors.textSecondary)),
      ),
    );

Widget _toggle(String title, String sub, bool on, VoidCallback onTap) =>
    GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 6.h),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: AppText.custom(
                          size: 14,
                          weight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                  SizedBox(height: 2.h),
                  Text(sub,
                      style: AppText.custom(
                          size: 12,
                          weight: FontWeight.w500,
                          color: AppColors.textMuted)),
                ],
              ),
            ),
            Semantics(
              toggled: on,
              label: title,
              child: Container(
                width: 46.w,
                height: 26.h,
                padding: EdgeInsets.all(3.r),
                alignment: on ? Alignment.centerRight : Alignment.centerLeft,
                decoration: BoxDecoration(
                    color: on ? AppColors.navy : AppColors.borderInput,
                    borderRadius: BorderRadius.circular(999)),
                child: Container(
                    width: 20.h,
                    height: 20.h,
                    decoration: const BoxDecoration(
                        color: AppColors.white, shape: BoxShape.circle)),
              ),
            ),
          ],
        ),
      ),
    );

/// "Complete by" date field (webapp `<input type="date">`), with a clear ×.
Widget _dateField(BuildContext context, DateTime? value,
        ValueChanged<DateTime?> onChanged) =>
    GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () async {
        final now = DateTime.now();
        final d = await showDatePicker(
          context: context,
          initialDate: value ?? now,
          firstDate: DateTime(now.year - 2),
          lastDate: DateTime(now.year + 5),
        );
        if (d != null) onChanged(d);
      },
      child: Container(
        height: 46.h,
        padding: EdgeInsets.symmetric(horizontal: 12.w),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(11.r),
          border: Border.all(color: AppColors.borderInput),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(value == null ? 'No deadline' : absoluteDate(value),
                  style: AppText.custom(
                      size: 14,
                      weight: FontWeight.w500,
                      color: value == null
                          ? AppColors.textPlaceholder
                          : AppColors.textPrimary)),
            ),
            if (value != null)
              GestureDetector(
                onTap: () => onChanged(null),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8.w),
                  child: Semantics(
                      label: 'Clear deadline',
                      button: true,
                      child: Icon(PhosphorIconsBold.x,
                          size: 14.sp, color: AppColors.textMuted)),
                ),
              ),
            Icon(PhosphorIconsRegular.calendarBlank,
                size: 17.sp, color: AppColors.textMuted),
          ],
        ),
      ),
    );

Widget _hint(String t) => Padding(
      padding: EdgeInsets.only(top: 6.h),
      child: Text(t,
          style: AppText.custom(
              size: 12,
              weight: FontWeight.w500,
              color: AppColors.textPlaceholder)),
    );

Widget _label(String t) => Padding(
      padding: EdgeInsets.only(bottom: 7.h),
      child: Text(t,
          style: AppText.custom(
              size: 13,
              weight: FontWeight.w600,
              color: AppColors.textSecondary)),
    );

Future<File?> _pick(List<String> extensions) async {
  final r = await FilePicker.platform.pickFiles(
      type: FileType.custom, allowedExtensions: extensions, withData: false);
  final path = r?.files.single.path;
  return path == null ? null : File(path);
}

// ── New course ──

class _NewCoursePanel extends ConsumerStatefulWidget {
  const _NewCoursePanel();

  @override
  ConsumerState<_NewCoursePanel> createState() => _NewCoursePanelState();
}

class _NewCoursePanelState extends ConsumerState<_NewCoursePanel> {
  final _title = TextEditingController();
  bool _sequential = true;
  bool _mandatory = false;
  DateTime? _deadline;
  bool _creating = false;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final t = _title.text.trim();
    if (t.isEmpty) {
      ref.read(toastProvider.notifier).showInfo('Type a course title first');
      return;
    }
    setState(() => _creating = true);
    try {
      final id = await ref.read(courseEditorRemoteProvider).createCourse(
          title: t,
          isSequential: _sequential,
          isMandatory: _mandatory,
          deadline: _deadline);
      if (!mounted) return;
      ref
          .read(toastProvider.notifier)
          .show('"$t" created — add modules and content');
      ref.read(lmsCoursesControllerProvider.notifier).reload();
      context.pushReplacement('${Routes.lmsBuilder}?id=$id');
    } on Object {
      // The shell toasts the server's refusal.
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _Shell(
      title: 'New course',
      child: ListView(
        padding: EdgeInsets.fromLTRB(18.w, 16.h, 18.w, 40.h),
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _title,
                  style: AppText.custom(
                      size: 14,
                      weight: FontWeight.w600,
                      color: AppColors.textPrimary),
                  decoration: _inputDeco('Course title'),
                ),
              ),
              SizedBox(width: 10.w),
              _primaryButton(_creating ? 'Creating…' : 'Create course',
                  _creating ? null : _create),
            ],
          ),
          SizedBox(height: 14.h),
          _card(
            title: 'Completion Rules',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _toggle(
                    'Sequential Modules',
                    'Must finish each before unlocking next',
                    _sequential,
                    () => setState(() => _sequential = !_sequential)),
                _toggle('Mandatory course', 'Required before accessing Clozr',
                    _mandatory, () => setState(() => _mandatory = !_mandatory)),
                SizedBox(height: 10.h),
                _label('Complete by'),
                _dateField(
                    context, _deadline, (d) => setState(() => _deadline = d)),
                _hint('Leave empty for no fixed deadline.'),
                SizedBox(height: 10.h),
                Text('You can change these anytime from the course editor.',
                    style: AppText.custom(
                        size: 12,
                        weight: FontWeight.w500,
                        color: AppColors.textPlaceholder)),
              ],
            ),
          ),
          SizedBox(height: 14.h),
          ClozrCard(
            radius: 16,
            padding: EdgeInsets.symmetric(horizontal: 22.w, vertical: 40.h),
            child: Column(
              children: [
                Container(
                  width: 56.r,
                  height: 56.r,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: AppColors.blueSubtle,
                      borderRadius: BorderRadius.circular(16.r)),
                  child: Icon(PhosphorIconsFill.graduationCap,
                      size: 26.sp, color: AppColors.navy),
                ),
                SizedBox(height: 14.h),
                Text('Start a new course',
                    style: AppText.custom(
                        size: 17,
                        weight: FontWeight.w700,
                        color: AppColors.textPrimary)),
                SizedBox(height: 6.h),
                Text(
                    'Type a course title above and hit Create — modules, videos and resources come next.',
                    textAlign: TextAlign.center,
                    style: AppText.custom(
                        size: 13.5,
                        weight: FontWeight.w500,
                        color: AppColors.textMuted,
                        height: 1.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Editor ──

enum _Assign { all, none, roles }

class _CourseEditorForm extends ConsumerStatefulWidget {
  const _CourseEditorForm({super.key, required this.initial});
  final EditorCourse initial;

  @override
  ConsumerState<_CourseEditorForm> createState() => _CourseEditorFormState();
}

class _CourseEditorFormState extends ConsumerState<_CourseEditorForm> {
  late final _title = TextEditingController(text: widget.initial.title);
  late final _desc = TextEditingController(text: widget.initial.description);
  final _moduleTitle = TextEditingController();
  final _moduleFocus = FocusNode();
  late bool _sequential = widget.initial.isSequential;
  late bool _mandatory = widget.initial.isMandatory;
  late DateTime? _deadline = widget.initial.deadline;
  late _Assign _assign = widget.initial.isUniversal
      ? _Assign.all
      : (widget.initial.hasAssignedRoles ? _Assign.roles : _Assign.none);
  late final bool _hadRoles = widget.initial.hasAssignedRoles;
  late String _selectedId =
      widget.initial.modules.isEmpty ? '' : widget.initial.modules.first.id;
  String _titledModuleId = '';

  bool _saving = false;
  bool _publishing = false;
  bool _working = false;
  bool _adding = false;
  bool _reordering = false;
  bool _pdfBusy = false;
  bool _thumbBusy = false;

  /// Video upload state machine: '' idle, requesting, uploading, attaching, error.
  String _upStep = '';
  int _upPct = 0;
  String _upError = '';
  CancelToken? _upCancel;
  Timer? _encodingTimer;

  String get _id => widget.initial.id;
  CourseEditorRemoteDataSource get _remote =>
      ref.read(courseEditorRemoteProvider);
  ToastController get _toast => ref.read(toastProvider.notifier);

  @override
  void initState() {
    super.initState();
    _moduleFocus.addListener(() {
      if (!_moduleFocus.hasFocus) _renameSelected();
    });
    // Webapp useEncodingWatch: re-check processing videos every 15 s.
    _encodingTimer =
        Timer.periodic(const Duration(seconds: 15), (_) => _checkEncoding());
  }

  @override
  void dispose() {
    _encodingTimer?.cancel();
    _upCancel?.cancel();
    _title.dispose();
    _desc.dispose();
    _moduleTitle.dispose();
    _moduleFocus.dispose();
    super.dispose();
  }

  void _refresh() {
    ref.invalidate(editorCourseProvider(_id));
    ref.read(lmsCoursesControllerProvider.notifier).reload();
  }

  Future<bool> _run(Future<void> Function() call) async {
    try {
      await call();
      return true;
    } on Object {
      return false; // the shell's failure toast carries the server message
    }
  }

  Future<void> _checkEncoding() async {
    final course = ref.read(editorCourseProvider(_id)).valueOrNull;
    if (course == null || !mounted) return;
    for (final v in course.videos.where((v) => v.isProcessing)) {
      try {
        final s = await _remote.streamStatus(v.bunnyVideoId);
        if (s == 4 || s == 5 || s == 6) {
          if (mounted) ref.invalidate(editorCourseProvider(_id));
          return;
        }
      } on Object {
        // Best-effort; the next tick retries.
      }
    }
  }

  Map<String, dynamic> _patch(EditorCourse course) => {
        'title': _title.text.trim().isEmpty ? course.title : _title.text.trim(),
        'description': _desc.text,
        'is_sequential': _sequential,
        'is_mandatory': _mandatory,
        'deadline': deadlineWire(_deadline),
        if (_assign == _Assign.all) 'assigned_to_role_ids': ['all'],
        if (_assign == _Assign.none) 'assigned_to_role_ids': <String>[],
      };

  /// Webapp `persist`: PATCH the form, then commit any staged thumbnail.
  Future<bool> _persist(EditorCourse course) async {
    final ok = await _run(() => _remote.updateCourse(_id, _patch(course)));
    if (!ok) return false;
    await _run(() => _remote.saveCourse(_id));
    _refresh();
    return true;
  }

  Future<void> _save(EditorCourse course) async {
    setState(() => _saving = true);
    final ok = await _persist(course);
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) _toast.show('Course saved');
  }

  Future<void> _publish(EditorCourse course) async {
    setState(() => _publishing = true);
    final ok = await _persist(course) && await _run(() => _remote.publish(_id));
    if (!mounted) return;
    setState(() => _publishing = false);
    if (ok) {
      _toast.show(
          '"${_title.text.trim().isEmpty ? course.title : _title.text.trim()}" published');
      _refresh();
    }
  }

  Future<void> _unpublish() async {
    setState(() => _working = true);
    final ok = await _run(() => _remote.draft(_id));
    if (!mounted) return;
    setState(() => _working = false);
    if (ok) {
      _toast.showInfo('Course moved to draft');
      _refresh();
    }
  }

  Future<void> _addModule(EditorCourse course) async {
    setState(() => _adding = true);
    String newId = '';
    final ok = await _run(() async =>
        newId = await _remote.addModule(_id, course.modules.length));
    if (!mounted) return;
    setState(() {
      _adding = false;
      if (ok && newId.isNotEmpty) _selectedId = newId;
    });
    if (ok) _refresh();
  }

  Future<void> _renameSelected() async {
    final course = ref.read(editorCourseProvider(_id)).valueOrNull;
    final mod =
        course?.modules.where((m) => m.id == _titledModuleId).firstOrNull;
    final next = _moduleTitle.text.trim();
    if (mod == null || next.isEmpty || next == mod.title) return;
    if (await _run(() => _remote.renameModule(_id, mod.id, next))) _refresh();
  }

  Future<void> _moveModule(EditorCourse course, int index, int dir) async {
    final ids = moveId([for (final m in course.modules) m.id], index, dir);
    if (ids == null || _reordering) return;
    setState(() => _reordering = true);
    final ok = await _run(() => _remote.reorderModules(_id, ids));
    if (!mounted) return;
    setState(() => _reordering = false);
    if (ok) _refresh();
  }

  Future<void> _moveVideo(EditorModule mod, int index, int dir) async {
    final ids = moveId([for (final v in mod.videos) v.id], index, dir);
    if (ids == null || _reordering) return;
    setState(() => _reordering = true);
    final ok = await _run(() => _remote.reorderVideos(mod.id, ids));
    if (!mounted) return;
    setState(() => _reordering = false);
    if (ok) _refresh();
  }

  Future<bool> _confirm(String title, String body, String action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(action, style: const TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _removeModule(EditorCourse course, EditorModule mod) async {
    if (course.modules.length <= 1) {
      _toast.showInfo('A course needs at least one module');
      return;
    }
    final go = await _confirm(
        'Delete "${mod.title}"?',
        "The module's video and resources are removed. Learners who completed it keep their progress record.",
        'Delete module');
    if (!go || !mounted) return;
    if (await _run(() => _remote.deleteModule(_id, mod.id))) {
      if (_selectedId == mod.id) {
        setState(() =>
            _selectedId = course.modules.firstWhere((m) => m.id != mod.id).id);
      }
      _toast.showInfo('Module removed');
      _refresh();
    }
  }

  Future<void> _pickVideo(EditorModule mod) async {
    final File? file;
    try {
      file = await _pick(['mp4', 'mov', 'webm']);
    } on Object catch (e) {
      _toast.showError('Could not open the file picker: $e');
      return;
    }
    if (file == null || !mounted) return;
    final name = file.path.split(Platform.pathSeparator).last;
    final title = name.replaceFirst(RegExp(r'\.[^./]+$'), '');
    final cancel = CancelToken();
    _upCancel = cancel;
    setState(() {
      _upError = '';
      _upStep = 'requesting';
    });
    try {
      await _remote.uploadVideo(
        moduleId: mod.id,
        file: file,
        title: title,
        position: mod.videos.length,
        cancel: cancel,
        onStep: (s) {
          if (mounted) setState(() => _upStep = s);
        },
        onProgress: (p) {
          if (mounted && p != _upPct) setState(() => _upPct = p);
        },
      );
      if (!mounted) return;
      setState(() => _upStep = '');
      _refresh();
    } on Object catch (e) {
      if (!mounted || cancel.isCancelled) return;
      setState(() {
        _upStep = 'error';
        _upError = e is AppError ? e.message : 'The upload failed.';
      });
    }
  }

  Future<void> _pickPdf(EditorModule mod) async {
    final File? file;
    try {
      file = await _pick(['pdf']);
    } on Object catch (e) {
      _toast.showError('Could not open the file picker: $e');
      return;
    }
    if (file == null || !mounted) return;
    setState(() => _pdfBusy = true);
    final ok = await _run(() => _remote.attachPdf(mod.id, file!));
    if (!mounted) return;
    setState(() => _pdfBusy = false);
    if (ok) {
      _toast.show('Resource attached');
      _refresh();
    }
  }

  Future<void> _pickThumb() async {
    final File? file;
    try {
      file = await _pick(['jpg', 'jpeg', 'png', 'webp', 'gif']);
    } on Object catch (e) {
      _toast.showError('Could not open the file picker: $e');
      return;
    }
    if (file == null || !mounted) return;
    setState(() => _thumbBusy = true);
    final ok = await _run(() => _remote.stageThumbnail(_id, file!));
    if (!mounted) return;
    setState(() => _thumbBusy = false);
    if (ok) {
      _toast.showInfo('Thumbnail staged — Save to apply');
      ref.invalidate(editorCourseProvider(_id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final course =
        ref.watch(editorCourseProvider(_id)).valueOrNull ?? widget.initial;
    final mods = course.modules;
    final selected =
        mods.where((m) => m.id == _selectedId).firstOrNull ?? mods.firstOrNull;
    if (selected != null && selected.id != _titledModuleId) {
      _titledModuleId = selected.id;
      _moduleTitle.text = selected.title;
    }
    final all = course.videos;
    final encoding = all.where((v) => !v.isEncoded && !v.encodingFailed).length;
    final failed = all.where((v) => v.encodingFailed).length;
    final published = course.isPublished;

    return _Shell(
      title: course.title,
      footer: LmsFooter(
        child: Row(
          children: [
            Expanded(
                flex: 10,
                child: _outlineButton(
                    'Cancel', () => context.go(Routes.lmsCourses))),
            SizedBox(width: 10.w),
            Expanded(
              flex: 14,
              child: published
                  ? GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _working ? null : _unpublish,
                      child: Container(
                        height: 46.h,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.tintGreen,
                          borderRadius: BorderRadius.circular(12.r),
                          border: Border.all(color: AppColors.success),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(PhosphorIconsFill.checkCircle,
                                size: 16.sp, color: AppColors.success),
                            SizedBox(width: 6.w),
                            Text(_working ? 'Working…' : 'Published',
                                style: AppText.custom(
                                    size: 14,
                                    weight: FontWeight.w700,
                                    color: AppColors.success)),
                          ],
                        ),
                      ),
                    )
                  : _primaryButton(
                      _publishing || _saving ? 'Publishing…' : 'Publish',
                      _publishing || _saving ? null : () => _publish(course),
                      icon: PhosphorIconsBold.rocketLaunch),
            ),
          ],
        ),
      ),
      child: ListView(
        padding: EdgeInsets.fromLTRB(18.w, 16.h, 18.w, 40.h),
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _title,
                  style: AppText.custom(
                      size: 14,
                      weight: FontWeight.w600,
                      color: AppColors.textPrimary),
                  decoration: _inputDeco('Course title'),
                ),
              ),
              SizedBox(width: 10.w),
              _primaryButton(_saving ? 'Saving…' : 'Save',
                  _saving ? null : () => _save(course)),
            ],
          ),
          SizedBox(height: 14.h),
          _modulesCard(course, selected),
          if (selected != null) ...[
            SizedBox(height: 14.h),
            _card(
              title: 'Module title',
              child: TextField(
                controller: _moduleTitle,
                focusNode: _moduleFocus,
                onSubmitted: (_) => _moduleFocus.unfocus(),
                style: AppText.custom(
                    size: 14,
                    weight: FontWeight.w600,
                    color: AppColors.textPrimary),
                decoration: _inputDeco('e.g. Fundamentals'),
              ),
            ),
            SizedBox(height: 14.h),
            _videoCard(selected),
            SizedBox(height: 14.h),
            _resourcesCard(selected),
            SizedBox(height: 14.h),
            _thumbCard(course),
          ],
          if (encoding > 0 || failed > 0) ...[
            SizedBox(height: 14.h),
            _encodingNotice(encoding, failed, published),
          ],
          SizedBox(height: 14.h),
          _settingsCard(course),
        ],
      ),
    );
  }

  Widget _iconBtn(IconData icon, String label, VoidCallback? onTap) =>
      Semantics(
        label: label,
        button: true,
        enabled: onTap != null,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.all(6.r),
            child: Icon(icon,
                size: 16.sp,
                color: onTap == null
                    ? AppColors.borderInput
                    : AppColors.textMuted),
          ),
        ),
      );

  Widget _modulesCard(EditorCourse course, EditorModule? selected) {
    final mods = course.modules;
    return _card(
      title: 'Modules',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < mods.length; i++)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _selectedId = mods[i].id),
              child: Container(
                margin: EdgeInsets.only(bottom: 6.h),
                padding: EdgeInsets.fromLTRB(12.w, 6.h, 4.w, 6.h),
                decoration: BoxDecoration(
                  color: mods[i].id == selected?.id
                      ? AppColors.blueSubtle
                      : AppColors.white,
                  borderRadius: BorderRadius.circular(10.r),
                  border: Border.all(
                      color: mods[i].id == selected?.id
                          ? AppColors.navy
                          : AppColors.borderCardSoft),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('${i + 1}. ${mods[i].title}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.custom(
                              size: 14,
                              weight: FontWeight.w600,
                              color: AppColors.textPrimary)),
                    ),
                    if (mods.length > 1) ...[
                      _iconBtn(
                          PhosphorIconsBold.caretUp,
                          'Move module up',
                          i > 0 && !_reordering
                              ? () => _moveModule(course, i, -1)
                              : null),
                      _iconBtn(
                          PhosphorIconsBold.caretDown,
                          'Move module down',
                          i < mods.length - 1 && !_reordering
                              ? () => _moveModule(course, i, 1)
                              : null),
                    ],
                    _iconBtn(PhosphorIconsRegular.trash, 'Delete module',
                        () => _removeModule(course, mods[i])),
                  ],
                ),
              ),
            ),
          SizedBox(height: 4.h),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _adding ? null : () => _addModule(course),
            child: Container(
              height: 42.h,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.bgLight,
                borderRadius: BorderRadius.circular(10.r),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(PhosphorIconsBold.plus,
                      size: 14.sp, color: AppColors.textSecondary),
                  SizedBox(width: 6.w),
                  Text(_adding ? 'Adding…' : 'Add module',
                      style: AppText.custom(
                          size: 13.5,
                          weight: FontWeight.w700,
                          color: AppColors.textSecondary)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fileRow(
          {required IconData icon,
          required String title,
          Widget? sub,
          List<Widget> trailing = const []}) =>
      Container(
        margin: EdgeInsets.only(bottom: 8.h),
        padding: EdgeInsets.fromLTRB(10.w, 8.h, 4.w, 8.h),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(11.r),
          border: Border.all(color: AppColors.borderCardSoft),
        ),
        child: Row(
          children: [
            Container(
              width: 36.r,
              height: 36.r,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: AppColors.bgLight,
                  borderRadius: BorderRadius.circular(9.r)),
              child: Icon(icon, size: 17.sp, color: AppColors.navy),
            ),
            SizedBox(width: 10.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: AppText.custom(
                          size: 14,
                          weight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                  if (sub != null) ...[SizedBox(height: 2.h), sub],
                ],
              ),
            ),
            ...trailing,
          ],
        ),
      );

  Widget _dropzone(
          {required String title,
          String? sub,
          required VoidCallback? onTap,
          IconData icon = PhosphorIconsRegular.folder}) =>
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 22.h, horizontal: 16.w),
          decoration: BoxDecoration(
            color: AppColors.bgScreen,
            borderRadius: BorderRadius.circular(12.r),
            border: Border.all(color: AppColors.borderInput),
          ),
          child: Column(
            children: [
              Icon(icon, size: 22.sp, color: AppColors.textSecondary),
              SizedBox(height: 6.h),
              Text(title,
                  textAlign: TextAlign.center,
                  style: AppText.custom(
                      size: 14,
                      weight: FontWeight.w700,
                      color: AppColors.textSecondary)),
              if (sub != null) ...[
                SizedBox(height: 2.h),
                Text(sub,
                    style: AppText.custom(
                        size: 12,
                        weight: FontWeight.w500,
                        color: AppColors.textPlaceholder)),
              ],
            ],
          ),
        ),
      );

  Widget _videoCard(EditorModule mod) {
    final busy = _upStep == 'requesting' ||
        _upStep == 'uploading' ||
        _upStep == 'attaching';
    return _card(
      title: 'Lesson Video',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < mod.videos.length; i++)
            _fileRow(
              icon: PhosphorIconsRegular.fileVideo,
              title: mod.videos[i].title,
              sub: Text(
                mod.videos[i].encodingFailed
                    ? 'Encoding failed — delete and re-upload this video'
                    : mod.videos[i].isEncoded
                        ? 'Ready'
                        : 'Encoding — not yet visible to learners',
                style: AppText.custom(
                    size: 12,
                    weight: FontWeight.w500,
                    color: mod.videos[i].encodingFailed
                        ? AppColors.error
                        : mod.videos[i].isEncoded
                            ? AppColors.textPlaceholder
                            : AppColors.warningDeep),
              ),
              trailing: [
                if (mod.videos.length > 1) ...[
                  _iconBtn(
                      PhosphorIconsBold.caretUp,
                      'Move video up',
                      i > 0 && !_reordering
                          ? () => _moveVideo(mod, i, -1)
                          : null),
                  _iconBtn(
                      PhosphorIconsBold.caretDown,
                      'Move video down',
                      i < mod.videos.length - 1 && !_reordering
                          ? () => _moveVideo(mod, i, 1)
                          : null),
                ],
                _iconBtn(PhosphorIconsRegular.trash, 'Delete video', () async {
                  if (await _run(() => _remote.deleteVideo(mod.videos[i].id)))
                    _refresh();
                }),
              ],
            ),
          if (busy)
            Container(
              padding: EdgeInsets.all(12.r),
              decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(11.r),
                  border: Border.all(color: AppColors.borderCardSoft)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    switch (_upStep) {
                      'requesting' => 'Preparing upload…',
                      'uploading' => 'Uploading… $_upPct%',
                      _ => 'Finishing…',
                    },
                    style: AppText.custom(
                        size: 13,
                        weight: FontWeight.w600,
                        color: AppColors.textPrimary),
                  ),
                  SizedBox(height: 8.h),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: _upStep == 'uploading'
                          ? _upPct / 100
                          : (_upStep == 'attaching' ? 1 : null),
                      minHeight: 6,
                      backgroundColor: AppColors.bgLight,
                      color: AppColors.navy,
                    ),
                  ),
                ],
              ),
            )
          else ...[
            _dropzone(
              icon: PhosphorIconsRegular.fileVideo,
              title: 'Click to upload a lesson video',
              sub: 'MP4, MOV or WebM',
              onTap: () => _pickVideo(mod),
            ),
            if (_upStep == 'error')
              Padding(
                padding: EdgeInsets.only(top: 8.h),
                child: Text(_upError,
                    style: AppText.custom(
                        size: 13,
                        weight: FontWeight.w600,
                        color: AppColors.error)),
              ),
          ],
        ],
      ),
    );
  }

  Widget _resourcesCard(EditorModule mod) => _card(
        title: 'Resources',
        optional: '( Optional )',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _dropzone(
              title: _pdfBusy ? 'Uploading…' : 'Attach PDFs · Max 50MB each',
              onTap: _pdfBusy ? null : () => _pickPdf(mod),
            ),
            if (mod.resources.isNotEmpty) SizedBox(height: 10.h),
            for (final r in mod.resources)
              _fileRow(
                icon: PhosphorIconsRegular.fileText,
                title: r.title,
                trailing: [
                  _iconBtn(PhosphorIconsBold.x, 'Remove resource', () async {
                    if (await _run(() => _remote.deleteResource(r.id)))
                      _refresh();
                  }),
                ],
              ),
          ],
        ),
      );

  Widget _thumbCard(EditorCourse course) {
    final preview = course.pendingThumbnailUrl.isNotEmpty
        ? course.pendingThumbnailUrl
        : course.thumbnailUrl;
    return _card(
      title: 'Course thumbnail',
      optional: '( Optional )',
      child: preview.isEmpty
          ? _dropzone(
              title: _thumbBusy ? 'Uploading…' : 'Attach jpeg/png · Max 5MB',
              onTap: _thumbBusy ? null : _pickThumb,
            )
          : Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10.r),
                  child: Image.network(preview,
                      width: 150.w,
                      height: 86.w,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                          width: 150.w,
                          height: 86.w,
                          color: AppColors.bgLight)),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (course.pendingThumbnailUrl.isNotEmpty)
                        Padding(
                          padding: EdgeInsets.only(bottom: 8.h),
                          child: Text('Pending — Save to apply',
                              style: AppText.custom(
                                  size: 12,
                                  weight: FontWeight.w700,
                                  color: AppColors.warningDeep)),
                        ),
                      SizedBox(
                          width: 110.w,
                          child: _outlineButton(
                              _thumbBusy ? 'Uploading…' : 'Replace',
                              _thumbBusy ? null : _pickThumb)),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _encodingNotice(int encoding, int failed, bool published) {
    final text = failed > 0
        ? '$failed video${failed == 1 ? '' : 's'} failed to encode. Delete and re-upload ${failed == 1 ? 'it' : 'them'} — '
            'the course can’t go live to learners until every video is encoded.'
        : '$encoding video${encoding == 1 ? '' : 's'} still encoding. '
            '${published ? 'Learners can’t see this course until encoding finishes.' : 'You can publish now — it becomes visible to learners once every video is encoded.'}';
    return Container(
      padding: EdgeInsets.all(12.r),
      decoration: BoxDecoration(
        color: failed > 0 ? AppColors.tintRed : AppColors.tintAmber,
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
              failed > 0
                  ? PhosphorIconsRegular.warningCircle
                  : PhosphorIconsRegular.clock,
              size: 16.sp,
              color: failed > 0 ? AppColors.error : AppColors.warningDeep),
          SizedBox(width: 8.w),
          Expanded(
              child: Text(text,
                  style: AppText.custom(
                      size: 12.5,
                      weight: FontWeight.w600,
                      color: AppColors.textPrimary,
                      height: 1.45))),
        ],
      ),
    );
  }

  Widget _settingsCard(EditorCourse course) {
    final assignLabel = switch (_assign) {
      _Assign.all => 'All users',
      _Assign.none => 'No automatic assignment',
      _Assign.roles => 'Keep current roles',
    };
    return _card(
      title: 'Course settings',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _label('Course description'),
          TextField(
            controller: _desc,
            minLines: 3,
            maxLines: 6,
            style: AppText.custom(
                size: 14,
                weight: FontWeight.w500,
                color: AppColors.textPrimary),
            decoration:
                _inputDeco('What will learners gain from this course ?'),
          ),
          SizedBox(height: 14.h),
          _label('Assign to'),
          PopupMenuButton<_Assign>(
            onSelected: (v) => setState(() => _assign = v),
            itemBuilder: (_) => [
              const PopupMenuItem(value: _Assign.all, child: Text('All users')),
              const PopupMenuItem(
                  value: _Assign.none, child: Text('No automatic assignment')),
              if (_hadRoles)
                const PopupMenuItem(
                    value: _Assign.roles, child: Text('Keep current roles')),
            ],
            child: Container(
              height: 46.h,
              padding: EdgeInsets.symmetric(horizontal: 12.w),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(11.r),
                border: Border.all(color: AppColors.borderInput),
              ),
              child: Row(
                children: [
                  Expanded(
                      child: Text(assignLabel,
                          style: AppText.custom(
                              size: 14,
                              weight: FontWeight.w600,
                              color: AppColors.textPrimary))),
                  Icon(PhosphorIconsBold.caretDown,
                      size: 13.sp, color: AppColors.textMuted),
                ],
              ),
            ),
          ),
          SizedBox(height: 16.h),
          Text('Completion Rules',
              style: AppText.custom(
                  size: 15,
                  weight: FontWeight.w700,
                  color: AppColors.textMuted2)),
          SizedBox(height: 6.h),
          _toggle(
              'Sequential Modules',
              'Must finish each before unlocking next',
              _sequential,
              () => setState(() => _sequential = !_sequential)),
          _toggle('Mandatory course', 'Required before accessing Clozr',
              _mandatory, () => setState(() => _mandatory = !_mandatory)),
          SizedBox(height: 14.h),
          Text('Deadline',
              style: AppText.custom(
                  size: 15,
                  weight: FontWeight.w700,
                  color: AppColors.textMuted2)),
          SizedBox(height: 8.h),
          _label('Complete by'),
          _dateField(context, _deadline, (d) => setState(() => _deadline = d)),
          _hint('Leave empty for no fixed deadline.'),
          SizedBox(height: 18.h),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () async {
              if (await deleteCourseByIdWithConfirm(context, ref,
                      id: _id, title: course.title) &&
                  mounted) {
                context.go(Routes.lmsCourses);
              }
            },
            child: Container(
              height: 46.h,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(12.r),
                border: Border.all(color: const Color(0xFFF3D2D2)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Delete the course',
                      style: AppText.custom(
                          size: 14,
                          weight: FontWeight.w700,
                          color: AppColors.error)),
                  SizedBox(width: 8.w),
                  Icon(PhosphorIconsRegular.trash,
                      size: 15.sp, color: AppColors.error),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
