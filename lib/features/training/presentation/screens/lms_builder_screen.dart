import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../application/providers/lms_providers.dart';
import '../components/lms_footer.dart';
import '../components/lms_header.dart';
import '../lms_nav.dart';

/// A locally-editable module inside the builder.
class _BuilderModule {
  String title;
  bool video;
  List<String> res;
  _BuilderModule({required this.title, this.video = false, List<String>? res}) : res = res ?? [];
}

/// Course Builder — title + create, editable module list, video/PDF/thumbnail
/// attach (simulated), description, role, sequential & mandatory toggles,
/// deadline and Publish/Cancel.
class LmsBuilderScreen extends ConsumerStatefulWidget {
  const LmsBuilderScreen({super.key});

  @override
  ConsumerState<LmsBuilderScreen> createState() => _LmsBuilderScreenState();
}

class _LmsBuilderScreenState extends ConsumerState<LmsBuilderScreen> {
  static const _roleCycle = ['All Roles', 'Sales rep', 'Project associate', 'Manager', 'Viewer'];

  final _titleCtrl = TextEditingController();
  final _subCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _deadlineCtrl = TextEditingController();
  final _selTitleCtrl = TextEditingController();

  final List<_BuilderModule> _modules = [];
  int _selIdx = -1;
  String _role = 'All Roles';
  bool _sequential = false;
  bool _mandatory = false;
  bool _loaded = false;
  bool _hasId = false;
  bool _created = false;
  String _publishLabel = 'Publish';

  @override
  void dispose() {
    _titleCtrl.dispose();
    _subCtrl.dispose();
    _descCtrl.dispose();
    _deadlineCtrl.dispose();
    _selTitleCtrl.dispose();
    super.dispose();
  }

  void _ensureLoaded() {
    if (_loaded) return;
    _loaded = true;
    final id = GoRouterState.of(context).uri.queryParameters['id'];
    final course = id == null ? null : ref.read(lmsCourseByIdProvider(id));
    if (course != null) {
      _hasId = true;
      _created = true;
      _titleCtrl.text = course.title;
      _subCtrl.text = course.sub;
      _descCtrl.text = course.desc;
      _deadlineCtrl.text = course.deadline;
      _role = course.role;
      _sequential = course.sequential;
      _mandatory = course.mandatory;
      _publishLabel = course.isPublished ? 'Republish' : 'Publish';
      for (final m in course.modules) {
        _modules.add(_BuilderModule(title: m.title, video: m.video, res: [...m.res]));
      }
      _selIdx = _modules.isEmpty ? -1 : 0;
      if (_selIdx >= 0) _selTitleCtrl.text = _modules[0].title;
    }
  }

  void _toast(String m) => ref.read(toastProvider.notifier).show(m);

  void _create() {
    if (_titleCtrl.text.trim().isEmpty) {
      _toast('Give the course a title first');
      return;
    }
    setState(() => _created = true);
    _toast('Course created as draft');
  }

  void _addModule() {
    setState(() {
      _modules.add(_BuilderModule(title: 'Module ${_modules.length + 1}'));
      _selIdx = _modules.length - 1;
      _selTitleCtrl.text = _modules[_selIdx].title;
    });
  }

  void _selectModule(int i) {
    setState(() {
      _selIdx = i;
      _selTitleCtrl.text = _modules[i].title;
    });
  }

  void _deleteModule(int i) {
    if (_modules.length <= 1) {
      _toast('A course must keep at least one module');
      return;
    }
    setState(() {
      _modules.removeAt(i);
      _selIdx = _selIdx.clamp(0, _modules.length - 1);
      _selTitleCtrl.text = _modules[_selIdx].title;
    });
  }

  void _attachVideo() {
    if (_selIdx < 0) return;
    setState(() => _modules[_selIdx].video = true);
    _toast('lesson-video.mp4 attached');
  }

  void _attachRes() {
    if (_selIdx < 0) return;
    setState(() => _modules[_selIdx].res.add('Guide ${_modules[_selIdx].res.length + 1}.pdf'));
    _toast('PDF attached');
  }

  void _publish() {
    if (_titleCtrl.text.trim().isEmpty) {
      _toast('Give the course a title first');
      return;
    }
    if (_modules.isEmpty) {
      _toast('Add at least one module');
      return;
    }
    _toast('Course published');
    lmsBack(context);
  }

  @override
  Widget build(BuildContext context) {
    _ensureLoaded();
    final hasSel = _selIdx >= 0 && _selIdx < _modules.length;

    return Container(
      color: AppColors.bgScreen,
      child: Column(
        children: [
          LmsHeader(
            onBack: () => lmsBack(context),
            title: Text('Course builder',
                style: AppText.custom(size: 20, weight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.4)),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(18.w, 16.h, 18.w, 40.h),
              children: [
                Text('Build Your Course', style: AppText.sectionTitle()),
                SizedBox(height: 3.h),
                Text('Start with a title, then add modules.',
                    style: AppText.custom(size: 13, weight: FontWeight.w500, color: AppColors.textMuted)),
                SizedBox(height: 12.h),
                Row(
                  children: [
                    Expanded(child: _boxField(_titleCtrl, 'Course title here', 46)),
                    if (!_hasId && !_created) ...[
                      SizedBox(width: 9.w),
                      GestureDetector(
                        onTap: _create,
                        child: Container(
                          height: 46.h,
                          padding: EdgeInsets.symmetric(horizontal: 18.w),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(color: AppColors.textBodyMuted, borderRadius: BorderRadius.circular(12.r)),
                          child: Text('Create', style: AppText.custom(size: 14, weight: FontWeight.w700, color: AppColors.white)),
                        ),
                      ),
                    ],
                  ],
                ),
                SizedBox(height: 9.h),
                _boxField(_subCtrl, 'Short subtitle (e.g. Core CRM workflows)', 42, fontSize: 13),
                Padding(
                  padding: EdgeInsets.fromLTRB(0, 20.h, 0, 8.h),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Modules', style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textMuted2)),
                      GestureDetector(
                        onTap: _addModule,
                        child: Container(
                          height: 38.h,
                          padding: EdgeInsets.symmetric(horizontal: 15.w),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(11.r)),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(PhosphorIconsBold.plus, size: 13.sp, color: AppColors.white),
                              SizedBox(width: 6.w),
                              Text('Add module', style: AppText.custom(size: 13, weight: FontWeight.w700, color: AppColors.white)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                _moduleList(),
                if (hasSel) ...[
                  SizedBox(height: 14.h),
                  _moduleEditor(),
                ],
                SizedBox(height: 14.h),
                _settingsCard(),
                if (_hasId) ...[
                  SizedBox(height: 14.h),
                  GestureDetector(
                    onTap: () {
                      _toast('Course deleted');
                      lmsBack(context);
                    },
                    child: Container(
                      height: 48.h,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        borderRadius: BorderRadius.circular(14.r),
                        border: Border.all(color: const Color(0xFFE6E7EA)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Delete the course', style: AppText.custom(size: 14, weight: FontWeight.w700, color: AppColors.textLabelAlt)),
                          SizedBox(width: 8.w),
                          Icon(PhosphorIconsRegular.trash, size: 16.sp, color: AppColors.textLabelAlt),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          LmsFooter(
            child: Row(
              children: [
                Expanded(
                  flex: 10,
                  child: GestureDetector(
                    onTap: () => lmsBack(context),
                    child: Container(
                      height: 50.h,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: AppColors.borderCardSoft, borderRadius: BorderRadius.circular(14.r)),
                      child: Text('Cancel', style: AppText.custom(size: 14.5, weight: FontWeight.w700, color: AppColors.textSecondary)),
                    ),
                  ),
                ),
                SizedBox(width: 10.w),
                Expanded(flex: 14, child: LmsCtaButton(label: _publishLabel, onTap: _publish)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _moduleList() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: AppColors.borderCardSoft),
      ),
      padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 4.h),
      child: _modules.isEmpty
          ? Padding(
              padding: EdgeInsets.symmetric(vertical: 14.h, horizontal: 12.w),
              child: Text('No modules yet — add your first module.',
                  style: AppText.custom(size: 13, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
            )
          : Column(
              children: [
                for (int i = 0; i < _modules.length; i++)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _selectModule(i),
                    child: Container(
                      padding: EdgeInsets.all(12.r),
                      decoration: BoxDecoration(
                        color: i == _selIdx ? const Color(0xFFEEF1F4) : Colors.transparent,
                        borderRadius: BorderRadius.circular(11.r),
                        border: i == _selIdx
                            ? null
                            : const Border(bottom: BorderSide(color: AppColors.bgLight)),
                      ),
                      child: Row(
                        children: [
                          Text('${i + 1}.', style: AppText.custom(size: 13, weight: FontWeight.w700, color: AppColors.textPlaceholder)),
                          SizedBox(width: 10.w),
                          Expanded(
                            child: Text(_modules[i].title.isEmpty ? 'Untitled module' : _modules[i].title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.custom(size: 14, weight: FontWeight.w600, color: AppColors.textBody)),
                          ),
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _deleteModule(i),
                            child: SizedBox(
                              width: 30.w,
                              height: 30.w,
                              child: Icon(PhosphorIconsRegular.trash, size: 16.sp, color: const Color(0xFFC2C6CD)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _moduleEditor() {
    final mod = _modules[_selIdx];
    return ClozrCard(
      radius: 16,
      padding: EdgeInsets.all(16.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Module title', style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary)),
          SizedBox(height: 10.h),
          _boxField(_selTitleCtrl, 'Module title', 44, radius: 11, onChanged: (v) => setState(() => mod.title = v)),
          SizedBox(height: 18.h),
          Text('Lesson Video', style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary)),
          if (mod.video) ...[
            SizedBox(height: 10.h),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 13.h),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FAF3),
                borderRadius: BorderRadius.circular(12.r),
                border: Border.all(color: const Color(0xFFCBE8D4)),
              ),
              child: Row(
                children: [
                  Icon(PhosphorIconsFill.video, size: 20.sp, color: AppColors.success),
                  SizedBox(width: 10.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('lesson-video.mp4', style: AppText.custom(size: 13, weight: FontWeight.w700, color: AppColors.textPrimary)),
                        Text('214 MB · Uploaded', style: AppText.custom(size: 11.5, weight: FontWeight.w500, color: AppColors.textMuted)),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: _attachVideo,
                    child: Container(
                      height: 30.h,
                      padding: EdgeInsets.symmetric(horizontal: 12.w),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        borderRadius: BorderRadius.circular(9.r),
                        border: Border.all(color: const Color(0xFFE6E7EA)),
                      ),
                      child: Text('Replace', style: AppText.custom(size: 12, weight: FontWeight.w700, color: AppColors.textSecondary)),
                    ),
                  ),
                ],
              ),
            ),
          ],
          SizedBox(height: 10.h),
          _dropzone(
            onTap: _attachVideo,
            padV: 26,
            child: Column(
              children: [
                Container(
                  width: 40.w,
                  height: 40.w,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: AppColors.blueSubtle, borderRadius: BorderRadius.circular(11.r)),
                  child: Icon(PhosphorIconsRegular.videoCamera, size: 20.sp, color: AppColors.blueBright),
                ),
                SizedBox(height: 9.h),
                Text('Click to upload or drag & drop', style: AppText.custom(size: 13.5, weight: FontWeight.w700, color: AppColors.textSecondary)),
                SizedBox(height: 3.h),
                Text('MP4 or MOV · Max 2GB', style: AppText.custom(size: 11.5, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
              ],
            ),
          ),
          SizedBox(height: 9.h),
          Center(
            child: Text('Videos cannot be deleted — only replaced',
                style: AppText.custom(size: 11.5, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
          ),
          SizedBox(height: 18.h),
          Text.rich(TextSpan(
            style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary),
            children: [
              const TextSpan(text: 'Resources '),
              TextSpan(text: '( Optional )', style: AppText.custom(size: 15, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
            ],
          )),
          for (final r in mod.res) ...[
            SizedBox(height: 9.h),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 13.w, vertical: 10.h),
              decoration: BoxDecoration(
                color: AppColors.bgScreen,
                borderRadius: BorderRadius.circular(11.r),
                border: Border.all(color: AppColors.borderCardSoft),
              ),
              child: Row(
                children: [
                  Icon(PhosphorIconsFill.filePdf, size: 17.sp, color: AppColors.error),
                  SizedBox(width: 9.w),
                  Expanded(child: Text(r, style: AppText.custom(size: 13, weight: FontWeight.w600, color: AppColors.textBody))),
                ],
              ),
            ),
          ],
          SizedBox(height: 10.h),
          _dropzone(
            onTap: _attachRes,
            padV: 18,
            child: Column(
              children: [
                Icon(PhosphorIconsRegular.folderOpen, size: 22.sp, color: AppColors.textMuted2),
                SizedBox(height: 7.h),
                Text('Attach PDFs · Max 50MB each', style: AppText.custom(size: 12.5, weight: FontWeight.w600, color: AppColors.textLabelAlt)),
              ],
            ),
          ),
          SizedBox(height: 18.h),
          Text.rich(TextSpan(
            style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textPrimary),
            children: [
              const TextSpan(text: 'Course thumbnail '),
              TextSpan(text: '( Optional )', style: AppText.custom(size: 15, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
            ],
          )),
          SizedBox(height: 10.h),
          _dropzone(
            onTap: () => _toast('Thumbnail attached'),
            padV: 18,
            child: Column(
              children: [
                Icon(PhosphorIconsRegular.image, size: 22.sp, color: AppColors.textMuted2),
                SizedBox(height: 7.h),
                Text('Attach jpeg · Max 5MB', style: AppText.custom(size: 12.5, weight: FontWeight.w600, color: AppColors.textLabelAlt)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _settingsCard() {
    return ClozrCard(
      radius: 16,
      padding: EdgeInsets.all(16.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Course settings', style: AppText.custom(size: 16, weight: FontWeight.w800, color: AppColors.textPrimary)),
          SizedBox(height: 14.h),
          Text('Course description', style: AppText.custom(size: 13.5, weight: FontWeight.w600, color: AppColors.textSecondary)),
          SizedBox(height: 9.h),
          _boxField(_descCtrl, 'What will learners gain from this course ?', 92, fontSize: 13.5, multiline: true, radius: 12),
          SizedBox(height: 14.h),
          Text('Assign to', style: AppText.custom(size: 13.5, weight: FontWeight.w600, color: AppColors.textSecondary)),
          SizedBox(height: 9.h),
          GestureDetector(
            onTap: () => setState(() => _role = _roleCycle[(_roleCycle.indexOf(_role) + 1) % _roleCycle.length]),
            child: Container(
              height: 46.h,
              padding: EdgeInsets.symmetric(horizontal: 14.w),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(12.r),
                border: Border.all(color: AppColors.borderInput),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_role, style: AppText.custom(size: 14, weight: FontWeight.w600, color: AppColors.textBody)),
                  Icon(PhosphorIconsBold.caretDown, size: 13.sp, color: AppColors.textMuted2),
                ],
              ),
            ),
          ),
          SizedBox(height: 18.h),
          Text('Completion Rules', style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textMuted2)),
          SizedBox(height: 12.h),
          _toggleRow('Sequential Modules', 'Must finish each before unlocking next', _sequential,
              () => setState(() => _sequential = !_sequential)),
          SizedBox(height: 14.h),
          _toggleRow('Mandatory course', 'Required before accessing Clozr', _mandatory,
              () => setState(() => _mandatory = !_mandatory)),
          SizedBox(height: 18.h),
          Text('Deadline', style: AppText.custom(size: 15, weight: FontWeight.w700, color: AppColors.textMuted2)),
          SizedBox(height: 10.h),
          Text('Complete By', style: AppText.custom(size: 13.5, weight: FontWeight.w600, color: AppColors.textSecondary)),
          SizedBox(height: 9.h),
          Container(
            height: 46.h,
            padding: EdgeInsets.symmetric(horizontal: 14.w),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: AppColors.borderInput),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _deadlineCtrl,
                    style: AppText.custom(size: 14, weight: FontWeight.w600, color: AppColors.textBody),
                    cursorColor: AppColors.blueBright,
                    decoration: const InputDecoration(isDense: true, border: InputBorder.none, hintText: 'e.g. 20 Aug 2026'),
                  ),
                ),
                Icon(PhosphorIconsRegular.calendarBlank, size: 18.sp, color: AppColors.textMuted2),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _toggleRow(String title, String sub, bool on, VoidCallback onTap) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppText.custom(size: 14, weight: FontWeight.w700, color: AppColors.textPrimary)),
              SizedBox(height: 1.h),
              Text(sub, style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textMuted)),
            ],
          ),
        ),
        SizedBox(width: 12.w),
        GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 46.w,
            height: 27.h,
            padding: EdgeInsets.all(3.r),
            alignment: on ? Alignment.centerRight : Alignment.centerLeft,
            decoration: BoxDecoration(
              color: on ? AppColors.navy : const Color(0xFFD8DADF),
              borderRadius: BorderRadius.circular(9999.r),
            ),
            child: Container(
              width: 21.w,
              height: 21.w,
              decoration: BoxDecoration(
                color: AppColors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: AppColors.black.withOpacity(0.25), blurRadius: 3, offset: const Offset(0, 1)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _dropzone({required VoidCallback onTap, required Widget child, double padV = 18}) {
    return GestureDetector(
      onTap: onTap,
      child: DottedBorderBox(
        padding: EdgeInsets.symmetric(vertical: padV.h, horizontal: 14.w),
        child: child,
      ),
    );
  }

  Widget _boxField(
    TextEditingController controller,
    String hint,
    double height, {
    double fontSize = 14,
    double radius = 12,
    bool multiline = false,
    ValueChanged<String>? onChanged,
  }) {
    return Container(
      height: multiline ? null : height.h,
      constraints: multiline ? BoxConstraints(minHeight: height.h) : null,
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: multiline ? 12.h : 0),
      alignment: multiline ? Alignment.topLeft : Alignment.centerLeft,
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(radius.r),
        border: Border.all(color: AppColors.borderInput),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        minLines: multiline ? 3 : 1,
        maxLines: multiline ? 5 : 1,
        style: AppText.custom(size: fontSize, weight: FontWeight.w500, color: AppColors.textBody),
        cursorColor: AppColors.blueBright,
        decoration: InputDecoration(
          isDense: true,
          border: InputBorder.none,
          hintText: hint,
          hintStyle: AppText.custom(size: fontSize, weight: FontWeight.w500, color: AppColors.textPlaceholder),
        ),
      ),
    );
  }
}

/// A dashed-border upload dropzone box.
class DottedBorderBox extends StatelessWidget {
  const DottedBorderBox({super.key, required this.child, required this.padding});
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedRectPainter(radius: 12.r, color: const Color(0xFFC9CCD2)),
      child: Padding(
        padding: padding,
        child: Center(child: child),
      ),
    );
  }
}

class _DashedRectPainter extends CustomPainter {
  _DashedRectPainter({required this.radius, required this.color});
  final double radius;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius));
    final path = Path()..addRRect(rrect);
    const dash = 5.0, gap = 4.0;
    for (final metric in path.computeMetrics()) {
      double dist = 0;
      while (dist < metric.length) {
        final len = dash.clamp(0, metric.length - dist).toDouble();
        canvas.drawPath(metric.extractPath(dist, dist + len), paint);
        dist += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRectPainter old) => old.color != color || old.radius != radius;
}
