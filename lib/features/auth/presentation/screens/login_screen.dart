import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../app/config/constants.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/network/app_error.dart';
import '../../application/providers/auth_providers.dart';
import '../../domain/entities/auth_session.dart';

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

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on AppError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Object {
      if (mounted) setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitCredentials() => _run(() async {
        final email = _email.text.trim();
        final password = _password.text;
        if (email.isEmpty || password.isEmpty) {
          throw const AppError(
            type: AppErrorType.validation,
            message: 'Enter your email and password.',
          );
        }
        final result = await ref
            .read(sessionControllerProvider.notifier)
            .login(email, password);
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
      });

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
    return Scaffold(
      backgroundColor: AppColors.bgScreen,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 32.h),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 342.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(AppConstants.brandName, style: AppText.logo()),
                  SizedBox(height: 6.h),
                  Text(
                    switch (_step) {
                      _LoginStep.credentials => 'Sign in to your workspace',
                      _LoginStep.challenge => 'Two-factor verification',
                      _LoginStep.enrol => 'Set up two-factor authentication',
                    },
                    style: AppText.bodyMuted(),
                  ),
                  SizedBox(height: 24.h),
                  if (_error != null) ...[
                    Container(
                      padding: EdgeInsets.all(12.r),
                      decoration: BoxDecoration(
                        color: AppColors.error.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(10.r),
                      ),
                      child: Text(
                        _error!,
                        style: AppText.caption(color: AppColors.error),
                      ),
                    ),
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
          ),
        ),
      ),
    );
  }

  List<Widget> _credentialFields() => [
        _field(_email, hint: 'Work email', keyboard: TextInputType.emailAddress),
        SizedBox(height: 12.h),
        _field(
          _password,
          hint: 'Password',
          obscure: _obscure,
          suffix: IconButton(
            onPressed: () => setState(() => _obscure = !_obscure),
            icon: Icon(
              _obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
              size: 18.r,
              color: AppColors.textMuted,
            ),
          ),
          onSubmitted: (_) => _submitCredentials(),
        ),
        SizedBox(height: 20.h),
        _primaryButton('Sign in', _submitCredentials),
      ];

  List<Widget> _challengeFields() => [
        Text(
          'Enter the code from your authenticator app, or one of your backup codes.',
          style: AppText.caption(),
        ),
        SizedBox(height: 12.h),
        _field(
          _code,
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
          hint: 'First 6-digit code',
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
                () async => setState(() => _backupCodes = const []),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller, {
    required String hint,
    bool obscure = false,
    TextInputType? keyboard,
    Widget? suffix,
    ValueChanged<String>? onSubmitted,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboard,
      onSubmitted: onSubmitted,
      style: AppText.body(),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: AppText.body(color: AppColors.textPlaceholder),
        filled: true,
        fillColor: AppColors.white,
        suffixIcon: suffix,
        contentPadding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 14.h),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10.r),
          borderSide: const BorderSide(color: AppColors.bgSubtle),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10.r),
          borderSide: const BorderSide(color: AppColors.bgSubtle),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10.r),
          borderSide: const BorderSide(color: AppColors.blueBright),
        ),
      ),
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
      child: Text('Back to sign in', style: AppText.caption(color: AppColors.blueBright)),
    );
  }
}
