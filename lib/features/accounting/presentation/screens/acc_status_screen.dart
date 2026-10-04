import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/utils/money_format.dart';
import '../../../../core/widgets/app_refresh.dart';
import '../../../../core/widgets/detail_app_bar.dart';
import '../../../../data/mock/status_meta.dart';
import '../../../crm/presentation/components/finance_widgets.dart';
import '../../application/providers/accounting_providers.dart';
import '../../application/providers/reports_providers.dart';
import '../../domain/entities/acc_setup.dart';
import '../components/acc_widgets.dart';
import '../config/accounting_copy.dart';

/// Accounting status (plan §4.13) — read-only: activation, the tenant profile,
/// the registration attributes and the activation gates. Setup itself is a
/// multi-step, CA-facing flow that stays on the web app.
class AccStatusScreen extends ConsumerWidget {
  const AccStatusScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(accountingStatusProvider);
    ref.invalidate(tenantProfileProvider);
    ref.invalidate(tenantAttributesProvider);
    ref.invalidate(gatesProvider);
    await settle([
      ref.read(accountingStatusProvider.future),
      ref.read(tenantProfileProvider.future),
    ]);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canSetup = ref.watch(accPermProvider('acc_setup')).read;
    return Container(
      color: AppColors.bgDetail,
      child: Column(
        children: [
          DetailAppBar(section: 'Accounting', name: 'Status', onBack: () => context.pop()),
          Expanded(
            child: AppRefresh(
              onRefresh: () => _refresh(ref),
              child: AccountingGate(
                allowInactive: true,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(16.w, 6.h, 16.w, 32.h),
                  children: [
                    if (canSetup) ...[
                      _profileCard(ref),
                      SizedBox(height: 14.h),
                      _attributesCard(ref),
                      SizedBox(height: 14.h),
                      _gatesCard(ref),
                    ] else
                      _summaryCard(ref),
                    SizedBox(height: 14.h),
                    const AccInfoBanner(
                      'Activation, opening balances, bank accounts and period closing are done on the web app.',
                      icon: PhosphorIconsRegular.desktop,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// For a role without `acc_setup`: all it can know is the gate result.
  Widget _summaryCard(WidgetRef ref) {
    final status = ref.watch(accountingStatusProvider).valueOrNull;
    final text = switch (status) {
      AccountingStatus.active => 'Accounting is active for this workspace.',
      AccountingStatus.paused => 'Accounting is activating or suspended.',
      _ => 'Accounting has not been activated for this workspace yet.',
    };
    return FinanceCard(
      title: 'Activation',
      child: Padding(
        padding: EdgeInsets.only(top: 4.h),
        child: Text(text, style: AppText.body(color: AppColors.textMuted)),
      ),
    );
  }

  Widget _profileCard(WidgetRef ref) {
    final async = ref.watch(tenantProfileProvider);
    final p = async.valueOrNull;
    final stateName = ref.watch(gstStateNameProvider);
    if (async.isLoading && p == null) return const _LoadingCard();
    if (p == null) {
      return const FinanceCard(
        title: 'Business profile',
        child: _Muted('No accounting profile yet. Start setup on the web app.'),
      );
    }
    final meta = StatusMeta$.accActivation[p.activationStatus];
    return FinanceCard(
      title: 'Business profile',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (meta != null) ...[
            SizedBox(height: 4.h),
            AccPill(StatusMeta$.accActivation, p.activationStatus),
            SizedBox(height: 6.h),
          ],
          MetaRow(label: 'Legal name', value: p.legalName ?? '—'),
          MetaRow(label: 'Entity type', value: label(entityTypeLabels, p.entityType)),
          MetaRow(label: 'State', value: stateName(p.stateCode)),
          MetaRow(label: 'PAN', value: p.pan ?? '—'),
          MetaRow(label: 'TAN', value: p.tan ?? '—'),
          MetaRow(label: 'Books start', value: formatApiDay(p.ledgerStartDate)),
          MetaRow(label: 'Prices usually', value: label(amountsAreLabels, p.defaultAmountsAre)),
          MetaRow(label: 'GST returns', value: label(const {'MONTHLY': 'Monthly', 'QRMP': 'Quarterly (QRMP)'}, p.returnFrequency), last: true),
        ],
      ),
    );
  }

  Widget _attributesCard(WidgetRef ref) {
    final async = ref.watch(tenantAttributesProvider);
    final attrs = [for (final a in async.valueOrNull ?? const <TenantAttribute>[]) if (a.isCurrent) a];
    if (async.isLoading && attrs.isEmpty) return const _LoadingCard();
    const names = {
      'REGISTRATION_STATUS': 'GST registration',
      'GSTIN': 'GSTIN',
      'ITC_ALLOWED': 'Input credit allowed',
      'IS_TDS_DEDUCTOR': 'Deducts TDS',
      'RULE_86B_EXEMPT': 'Rule 86B exempt',
      'RETURN_FREQUENCY': 'Return frequency',
      'PREV_FY_TURNOVER': 'Last year turnover',
    };
    return FinanceCard(
      title: 'Registration',
      child: attrs.isEmpty
          ? const _Muted('Nothing recorded yet.')
          : Column(
              children: [
                for (int i = 0; i < attrs.length; i++)
                  MetaRow(
                    label: names[attrs[i].attribute] ?? label(const {}, attrs[i].attribute),
                    value: attrs[i].attribute == 'REGISTRATION_STATUS'
                        ? label(registrationTypeLabels, attrs[i].display)
                        : attrs[i].display,
                    last: i == attrs.length - 1,
                  ),
              ],
            ),
    );
  }

  Widget _gatesCard(WidgetRef ref) {
    final async = ref.watch(gatesProvider);
    final report = async.valueOrNull;
    if (async.isLoading && report == null) return const _LoadingCard();
    if (report == null || report.gates.isEmpty) return const SizedBox.shrink();
    return FinanceCard(
      title: 'Activation checks',
      child: Column(
        children: [
          for (int i = 0; i < report.gates.length; i++)
            _gateRow(report.gates[i], last: i == report.gates.length - 1),
        ],
      ),
    );
  }

  Widget _gateRow(GateResult g, {required bool last}) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 10.h),
      decoration: last ? null : const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF3F4F5)))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(g.passed ? PhosphorIconsFill.checkCircle : PhosphorIconsFill.xCircle,
              size: 18.sp, color: g.passed ? AppColors.success : AppColors.error),
          SizedBox(width: 10.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(g.gate, style: AppText.custom(size: 13.5, weight: FontWeight.w700, color: AppColors.textPrimary)),
                if ((g.detail ?? '').isNotEmpty) ...[
                  SizedBox(height: 2.h),
                  Text(g.detail!, style: AppText.custom(size: 12, weight: FontWeight.w500, color: AppColors.textMuted, height: 1.4)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Muted extends StatelessWidget {
  const _Muted(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(top: 4.h),
        child: Text(text, style: AppText.body(color: AppColors.textMuted)),
      );
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) => FinanceCard(
        child: SizedBox(
          height: 60.h,
          child: const Center(child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.navy)),
        ),
      );
}
