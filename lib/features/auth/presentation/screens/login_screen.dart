import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../app/config/constants.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/network/app_error.dart';
import '../../../../core/storage/remembered_email.dart';
import '../../application/providers/auth_providers.dart';
import '../../domain/entities/auth_session.dart';
import '../components/login_backdrop.dart';

enum _LoginStep { credentials, challenge, enrol }

/// Email/password sign-in with both 2FA branches: code challenge for enrolled
/// devices, and forced TOTP enrolment when the org requires it.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();

  _LoginStep _step = _LoginStep.credentials;
  bool _busy = false;
  bool _obscure = true;
  String? _error;
  String? _challengeToken;
  String? _enrolmentToken;
  String _enrolMessage = '';
  TwoFactorEnrolment? _enrolment;
  List<String> _backupCodes = const [];

  /// Whether to keep the work email for next time. Starts on when one was
  /// remembered, so signing in again does not silently forget it.
  bool _remember = false;
  final _rememberedEmail = RememberedEmail();

  @override
  void initState() {
    super.initState();
    _restoreEmail();
  }

  /// Prefills the address the user asked to be remembered. Never a password:
  /// the session itself already survives a restart through the token store, so
  /// this only saves retyping.
  Future<void> _restoreEmail() async {
    final saved = await _rememberedEmail.read();
    if (saved == null || !mounted) return;
    setState(() {
      _email.text = saved;
      _remember = true;
    });
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(
    Future<void> Function() action, {
    String? Function(AppError error)? mapError,
  }) async {
    if (_busy) return; // guard the Enter path against a double submit
    setState(() {
      _busy = true;
      _error = null;
    });
    ref.read(signOutReasonProvider.notifier).state = null;
    try {
      await action();
    } on AppError catch (e) {
      if (mounted) setState(() => _error = mapError?.call(e) ?? e.message);
    } on Object {
      if (mounted)
        setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  Future<void> _submitCredentials() => _run(
        () async {
          final email = _email.text.trim();
          final password = _password.text;
          if (email.isEmpty || password.isEmpty) {
            throw const AppError(
              type: AppErrorType.validation,
              message: 'Enter your email and password.',
            );
          }
          if (!_emailPattern.hasMatch(email)) {
            throw const AppError(
              type: AppErrorType.validation,
              message: 'Enter a valid email address.',
            );
          }
          final result = await ref
              .read(sessionControllerProvider.notifier)
              .login(email, password);
          // Saved once the server has accepted the address — including when it
          // sends the user on to a 2FA challenge, which is still a valid sign-in
          // for an email worth remembering. Unticked clears whatever an earlier
          // sign-in stored.
          await _rememberedEmail.save(email, remember: _remember);
          if (!mounted) return;
          switch (result) {
            case LoginSuccess():
              break; // Router redirects via the session gate.
            case LoginTwoFactorRequired(:final challengeToken):
              setState(() {
                _challengeToken = challengeToken;
                _code.clear();
                _step = _LoginStep.challenge;
              });
            case LoginEnrolmentRequired(:final enrolmentToken, :final message):
              _enrolmentToken = enrolmentToken;
              _enrolMessage = message;
              final enrolment = await ref
                  .read(sessionControllerProvider.notifier)
                  .startEnrolment(enrolmentToken);
              if (!mounted) return;
              setState(() {
                _enrolment = enrolment;
                _code.clear();
                _step = _LoginStep.enrol;
              });
          }
        },
        // A refused sign-in shows the server's own words, as the webapp does
        // ("No active account found with the given credentials" — which also
        // covers a deactivated account). Only a bare 401 with no message
        // falls back, since "session expired" would mislead on a fresh sign-in.
        mapError: (e) => e.type == AppErrorType.unauthorized &&
                e.message == 'Your session has expired. Please sign in again.'
            ? 'Incorrect email or password.'
            : null,
      );

  Future<void> _submitCode() => _run(() async {
        final code = _code.text.trim();
        if (code.isEmpty) {
          throw const AppError(
            type: AppErrorType.validation,
            message: 'Enter the 6-digit code.',
          );
        }
        final controller = ref.read(sessionControllerProvider.notifier);
        if (_step == _LoginStep.challenge) {
          await controller.verifyTwoFactor(
            challengeToken: _challengeToken ?? '',
            code: code,
          );
        } else {
          final session = await controller.confirmEnrolment(
            enrolmentToken: _enrolmentToken ?? '',
            code: code,
          );
          if (session.backupCodes.isNotEmpty && mounted) {
            setState(() => _backupCodes = session.backupCodes);
          }
        }
      });

  @override
  Widget build(BuildContext context) {
    if (_backupCodes.isNotEmpty) return _backupCodesView();
    final reason = ref.watch(signOutReasonProvider);
    final signOutMessage =
        reason == null ? null : signOutReasonMessages[reason];
    return Scaffold(
      backgroundColor: AppColors.bgScreen,
      body: Stack(
        children: [
          const Positioned.fill(child: LoginBackdrop()),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 32.h),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: 400.w),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Brand lockup, centred above the card like the webapp's
                      // sign-in header. The logo sits on a square transparent
                      // canvas, so Align + ClipRect trim it to the artwork.
                      Center(
                        child: ClipRect(
                          child: Align(
                            widthFactor: 0.88,
                            heightFactor: 0.47,
                            child: Image.asset(
                              'assets/Clozr-Regular-1080px.png',
                              height: 40.h / 0.47,
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.medium,
                              semanticLabel: AppConstants.brandName,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: 24.h),
                      Container(
                        padding: EdgeInsets.fromLTRB(22.w, 26.h, 22.w, 22.h),
                        decoration: BoxDecoration(
                          color: AppColors.white,
                          borderRadius: BorderRadius.circular(16.r),
                          border: Border.all(color: AppColors.bgSubtle),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.navy.withOpacity(0.06),
                              blurRadius: 24,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              switch (_step) {
                                _LoginStep.credentials => 'Welcome back',
                                _LoginStep.challenge =>
                                  'Two-factor verification',
                                _LoginStep.enrol => 'Set up two-factor sign-in',
                              },
                              textAlign: TextAlign.center,
                              style: AppText.h1(),
                            ),
                            SizedBox(height: 4.h),
                            Text(
                              switch (_step) {
                                _LoginStep.credentials =>
                                  'Sign in to your account',
                                _LoginStep.challenge =>
                                  'One more step to sign in',
                                _LoginStep.enrol =>
                                  'Your organization requires it',
                              },
                              textAlign: TextAlign.center,
                              style: AppText.bodyMuted(),
                            ),
                            SizedBox(height: 22.h),
                            if (_error == null && signOutMessage != null) ...[
                              // The webapp's sign-out notice: why the server ended
                              // the last session, until the next sign-in attempt.
                              _notice(signOutMessage, Icons.info_outline,
                                  AppColors.blueBright),
                              SizedBox(height: 16.h),
                            ],
                            if (_error != null) ...[
                              _notice(_error!, Icons.error_outline,
                                  AppColors.error),
                              SizedBox(height: 16.h),
                            ],
                            ...switch (_step) {
                              _LoginStep.credentials => _credentialFields(),
                              _LoginStep.challenge => _challengeFields(),
                              _LoginStep.enrol => _enrolFields(),
                            },
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Icon + message banner (webapp's info / danger alert), tinted by [color].
  Widget _notice(String message, IconData icon, Color color) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(10.r),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(top: 1.h),
            child: Icon(icon, size: 16.r, color: color),
          ),
          SizedBox(width: 8.w),
          Expanded(child: Text(message, style: AppText.caption(color: color))),
        ],
      ),
    );
  }

  List<Widget> _credentialFields() => [
        _field(_email,
            label: 'Email',
            hint: 'you@company.com',
            keyboard: TextInputType.emailAddress,
            autofill: const [AutofillHints.username, AutofillHints.email],
            action: TextInputAction.next),
        SizedBox(height: 16.h),
        _field(
          _password,
          label: 'Password',
          hint: 'Enter your password',
          autofill: const [AutofillHints.password],
          action: TextInputAction.done,
          obscure: _obscure,
          suffix: IconButton(
            onPressed: () => setState(() => _obscure = !_obscure),
            icon: Icon(
              _obscure
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              size: 18.r,
              color: AppColors.textMuted,
            ),
          ),
          onSubmitted: (_) => _submitCredentials(),
        ),
        SizedBox(height: 8.h),
        _rememberRow(),
        SizedBox(height: 16.h),
        _primaryButton('Sign in', _submitCredentials),
        SizedBox(height: 14.h),
        Text(
          'Trouble signing in? Contact your administrator.',
          textAlign: TextAlign.center,
          style: AppText.caption(),
        ),
      ];

  /// "Remember me" — the email only, and it says so, so nobody reads it as a
  /// stored password.
  Widget _rememberRow() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _busy ? null : () => setState(() => _remember = !_remember),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 6.h),
        child: Row(
          children: [
            Container(
              width: 20.r,
              height: 20.r,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _remember ? AppColors.navy : AppColors.white,
                borderRadius: BorderRadius.circular(6.r),
                border: Border.all(
                    color: _remember ? AppColors.navy : AppColors.borderInput,
                    width: 1.5),
              ),
              child: _remember
                  ? Icon(Icons.check, size: 14.r, color: AppColors.white)
                  : null,
            ),
            SizedBox(width: 10.w),
            Text('Remember my email',
                style: AppText.custom(
                    size: 13,
                    weight: FontWeight.w600,
                    color: AppColors.textBody)),
          ],
        ),
      ),
    );
  }

  List<Widget> _challengeFields() => [
        Text(
          'Enter the code from your authenticator app, or one of your backup codes.',
          style: AppText.caption(),
        ),
        SizedBox(height: 12.h),
        _field(
          _code,
          label: 'Verification code',
          hint: '6-digit code',
          keyboard: TextInputType.number,
          onSubmitted: (_) => _submitCode(),
        ),
        SizedBox(height: 20.h),
        _primaryButton('Verify', _submitCode),
        SizedBox(height: 12.h),
        _backLink(),
      ];

  List<Widget> _enrolFields() => [
        Text(
          _enrolMessage.isNotEmpty
              ? _enrolMessage
              : 'Your organization requires two-factor authentication. Add this account to an authenticator app, then enter the first code.',
          style: AppText.caption(),
        ),
        SizedBox(height: 16.h),
        if (_enrolment != null) ...[
          Container(
            padding: EdgeInsets.all(14.r),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: AppColors.bgSubtle),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Secret key', style: AppText.captionStrong()),
                SizedBox(height: 6.h),
                SelectableText(
                  _enrolment!.secret,
                  style: AppText.bodyStrong(color: AppColors.blueBright),
                ),
              ],
            ),
          ),
          SizedBox(height: 16.h),
        ],
        _field(
          _code,
          label: 'First 6-digit code',
          hint: '123456',
          keyboard: TextInputType.number,
          onSubmitted: (_) => _submitCode(),
        ),
        SizedBox(height: 20.h),
        _primaryButton('Enable & sign in', _submitCode),
        SizedBox(height: 12.h),
        _backLink(),
      ];

  Widget _backupCodesView() {
    return Scaffold(
      backgroundColor: AppColors.bgScreen,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(24.r),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: 24.h),
              Text('Save your backup codes', style: AppText.h1()),
              SizedBox(height: 8.h),
              Text(
                'These are shown only once. Store them somewhere safe — each one signs you in if you lose your authenticator.',
                style: AppText.caption(),
              ),
              SizedBox(height: 16.h),
              Expanded(
                child: Container(
                  padding: EdgeInsets.all(14.r),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(12.r),
                    border: Border.all(color: AppColors.bgSubtle),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      _backupCodes.join('\n'),
                      style: AppText.bodyStrong(),
                    ),
                  ),
                ),
              ),
              SizedBox(height: 16.h),
              _primaryButton(
                "I've saved these — continue",
                () async {
                  // Tokens were already persisted in confirmEnrolment; promote
                  // the gate now that the one-time codes are acknowledged.
                  ref.read(sessionControllerProvider.notifier).finalizeLogin();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller, {
    required String label,
    required String hint,
    bool obscure = false,
    TextInputType? keyboard,
    Widget? suffix,
    ValueChanged<String>? onSubmitted,
    Iterable<String>? autofill,
    TextInputAction? action,
  }) {
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(10.r),
          borderSide: BorderSide(color: c, width: w),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: AppText.captionStrong(color: AppColors.textSecondary)),
        SizedBox(height: 6.h),
        TextField(
          controller: controller,
          obscureText: obscure,
          keyboardType: keyboard,
          textInputAction: action,
          autofillHints: autofill,
          enabled: !_busy,
          onSubmitted: onSubmitted,
          style: AppText.body(),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: AppText.body(color: AppColors.textPlaceholder),
            filled: true,
            fillColor: AppColors.bgPage,
            suffixIcon: suffix,
            contentPadding:
                EdgeInsets.symmetric(horizontal: 14.w, vertical: 14.h),
            border: border(AppColors.borderInput),
            enabledBorder: border(AppColors.borderInput),
            disabledBorder: border(AppColors.bgSubtle),
            focusedBorder: border(AppColors.blueBright, 1.5),
          ),
        ),
      ],
    );
  }

  Widget _primaryButton(String label, Future<void> Function() onTap) {
    return SizedBox(
      height: 48.h,
      child: FilledButton(
        onPressed: _busy ? null : () => onTap(),
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.navy,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10.r),
          ),
        ),
        child: _busy
            ? SizedBox(
                width: 20.r,
                height: 20.r,
                child: const CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.white,
                ),
              )
            : Text(label, style: AppText.bodyStrong(color: AppColors.white)),
      ),
    );
  }

  Widget _backLink() {
    return TextButton(
      onPressed: _busy
          ? null
          : () => setState(() {
                _step = _LoginStep.credentials;
                _error = null;
                _code.clear();
              }),
      child: Text('Back to sign in',
          style: AppText.caption(color: AppColors.blueBright)),
    );
  }
}
