import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_refresh.dart';
import '../../../../core/widgets/detail_app_bar.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/network/app_error.dart';
import '../../../../core/widgets/action_menu.dart';
import '../../../../core/widgets/error_state.dart';
import '../../../../core/widgets/list_skeleton.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../../notes/application/providers/notes_providers.dart';
import '../../../shell/application/providers/shell_providers.dart';
import '../../../../core/utils/relative_time.dart';
import '../../application/providers/audit_log_providers.dart';
import '../../application/providers/products_providers.dart';
import '../../../../core/utils/inr_format.dart';
import '../../domain/entities/audit_entry.dart';
import '../../domain/entities/package_composition.dart';
import '../../domain/entities/product.dart';
import '../components/crm_async.dart';
import '../components/finance_widgets.dart';

/// Product detail — header (name + active toggle + edit), description,
/// performance, pricing, details and notes.
class ProductDetailScreen extends ConsumerWidget {
  const ProductDetailScreen({super.key});

  /// Pull-to-refresh: the product list this record is read out of.
  Future<void> _refresh(WidgetRef ref, String id) async {
    ref.invalidate(productsProvider);
    // The row and its notes are their own calls; reloading only the list left
    // both stale under a pull.
    ref.invalidate(productDetailProvider(id));
    ref.invalidate(productNotesProvider(id));
    ref.invalidate(productActivityLogProvider(id));
    await settle([
      ref.read(productsProvider.future),
      ref.read(productDetailProvider(id).future),
      ref.read(productNotesProvider(id).future),
      ref.read(productActivityLogProvider(id).future),
    ]);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = GoRouterState.of(context).uri.queryParameters['id'] ?? '';
    final async = ref.watch(productsProvider);

    Widget scaffold(Widget child) => Container(
          color: AppColors.bgDetail,
          child: Column(
            children: [
              DetailAppBar(section: 'Product', onBack: () => context.pop()),
              Expanded(child: child),
            ],
          ),
        );

    return async.when(
      loading: () => scaffold(const DetailSkeleton()),
      error: (e, _) => scaffold(
        ErrorState.forError(crmAppError(e), onRetry: () => ref.invalidate(productsProvider)),
      ),
      data: (_) => _buildProduct(context, ref, id, scaffold),
    );
  }

  Widget _buildProduct(
    BuildContext context,
    WidgetRef ref,
    String id,
    Widget Function(Widget) scaffold,
  ) {
    // The item's own row wins over the list's copy: it is one call, and a
    // product beyond the loaded pages still opens. Null in mock mode and on
    // failure — then the list row stands, exactly as before.
    final product = ref.watch(productDetailProvider(id)).valueOrNull ??
        ref.watch(productByIdProvider(id));
    if (product == null) {
      return scaffold(const EmptyState(
        icon: PhosphorIconsRegular.package,
        title: 'Product not found',
        body: 'This catalog item may have been removed or you no longer have access to it.',
      ));
    }

    // The entity's own `notes` are the mock seed's; a real product's notes come
    // from the polymorphic notes endpoint, which is empty in mock mode.
    final fetched = ref.watch(productNotesProvider(id)).valueOrNull ?? const [];
    final notes = fetched.isNotEmpty
        ? [
            for (final n in fetched)
              NoteEntry(
                  initials: _initials(n.author),
                  author: n.author,
                  time: n.time,
                  body: n.body),
          ]
        : [
            for (final n in product.notes)
              NoteEntry(
                  initials: _initials(n.author),
                  author: n.author,
                  time: n.time,
                  body: n.body),
          ];

    return Container(
      color: AppColors.bgDetail,
      child: Column(
        children: [
          DetailAppBar(
            section: 'Product',
            name: product.name,
            onBack: () => context.pop(),
            trailing: DetailIconAction(
              icon: PhosphorIconsBold.dotsThreeVertical,
              onTap: () => _openMenu(context, ref, product),
            ),
          ),
          Expanded(
            child: AppRefresh(
              onRefresh: () => _refresh(ref, id),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(16.w, 6.h, 16.w, 24.h),
              children: [
                _headerCard(ref, product),
                SizedBox(height: 14.h),
                FinanceCard(
                  title: 'Description',
                  child: Text(_desc(product),
                      style: AppText.custom(size: 14, weight: FontWeight.w500, color: AppColors.textLabelAlt, height: 1.6)),
                ),
                SizedBox(height: 14.h),
                if (_performanceCard(product) case final card?) ...[
                  card,
                  SizedBox(height: 14.h),
                ],
                // A package's price is derived from what it contains, so the
                // composition belongs above the pricing that follows from it.
                if (product.composition case final comp?)
                  // The composition *is* the pricing for a package: its price
                  // is the derived total, and the per-unit GST rows below apply
                  // to a single product, not to a bundle whose components each
                  // carry their own rate.
                  _compositionCard(comp)
                else
                  _pricingCard(product),
                SizedBox(height: 14.h),
                FinanceCard(
                  title: 'Details',
                  child: Column(
                    children: [
                      // A field the org's Product layout does not expose comes
                      // back absent; an empty value cell reads as a rendering
                      // fault rather than as "not set".
                      MetaRow(label: 'Category', value: _orDash(product.cat)),
                      MetaRow(label: 'Billing unit', value: _orDash(product.unit)),
                      MetaRow(label: 'SKU / code', value: _orDash(product.code)),
                      MetaRow(label: 'HSN / SAC', value: _orDash(product.hsn), last: true),
                    ],
                  ),
                ),
                SizedBox(height: 14.h),
                NotesCard(
                  title: 'Notes',
                  countLabel: '${notes.length} ${notes.length == 1 ? 'note' : 'notes'}',
                  notes: notes,
                  onSend: (body) => _addNote(ref, id, body),
                ),
                if (ApiConfig.apiEnabled) ...[
                  SizedBox(height: 14.h),
                  _activityCard(ref, id),
                ],
              ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerCard(WidgetRef ref, Product product) {
    return FinanceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconChip(icon: productCategoryIcon(product.cat), size: 46, radius: 13, iconSize: 22),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8.w,
                      runSpacing: 4.h,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(product.name,
                            style: AppText.custom(size: 18, weight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.3)),
                        product.active
                            ? const StatusPill(label: 'Active', color: AppColors.success)
                            : const StatusPill(label: 'Inactive', color: AppColors.error),
                      ],
                    ),
                    SizedBox(height: 3.h),
                    // `product_code` is optional, and `product.id` is the
                    // `product_id` uuid — printing that as a fallback put a raw
                    // uuid on screen for every product created without a SKU.
                    Text([
                      if (product.code.isNotEmpty) product.code,
                      if (product.cat.isNotEmpty) product.cat,
                    ].join(' · '),
                        style: AppText.custom(size: 12.5, weight: FontWeight.w500, color: AppColors.textMuted)),
                    if (product.hsn.isNotEmpty) ...[
                      SizedBox(height: 3.h),
                      Text('# HSN/SAC ${product.hsn}',
                          style: AppText.custom(size: 12, weight: FontWeight.w600, color: AppColors.textPlaceholder)),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const ClozrDivider(margin: EdgeInsets.symmetric(vertical: 15)),
          Row(
            children: [
              Expanded(
                child: Text('Catalog item · used across quotes & deals',
                    style: AppText.custom(size: 11.5, weight: FontWeight.w500, color: AppColors.textPlaceholder)),
              ),
              SizedBox(width: 10.w),
              _pillButton(
                icon: PhosphorIconsRegular.power,
                label: product.active ? 'Deactivate' : 'Activate',
                onTap: () => _setActive(ref, product, !product.active),
              ),
              SizedBox(width: 8.w),
              _pillButton(
                icon: PhosphorIconsRegular.pencilSimple,
                label: 'Edit',
                onTap: () => ref.read(toastProvider.notifier).show('Edit product — coming soon'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pillButton({required IconData icon, required String label, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 38.h,
        padding: EdgeInsets.symmetric(horizontal: 13.w),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10.r),
          border: Border.all(color: const Color(0xFFE6E7EA)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15.sp, color: AppColors.textSecondary),
            SizedBox(width: 6.w),
            Text(label, style: AppText.custom(size: 12.5, weight: FontWeight.w600, color: AppColors.textBody)),
          ],
        ),
      ),
    );
  }

  /// Usage stats — hidden entirely when nothing backs them.
  ///
  /// No endpoint reports deals or revenue per catalog item, so on a live
  /// backend this card was three big blue zeros: "0 deals, ₹0 lifetime revenue,
  /// — avg", which reads as a product nobody ever sold rather than as a figure
  /// the server does not publish.
  Widget? _performanceCard(Product product) {
    if (product.deals == 0 && product.revNum == 0) return null;
    final perf = <(String, String)>[
      ('${product.deals}', 'Deals using this'),
      (product.revenue, 'Lifetime revenue'),
      (product.avg, 'Avg. per deal'),
    ];
    return FinanceCard(
      title: 'Performance',
      child: Padding(
        padding: EdgeInsets.only(top: 6.h),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final p in perf)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.$1, style: AppText.custom(size: 17, weight: FontWeight.w800, color: AppColors.blueBright, letterSpacing: -0.3)),
                    SizedBox(height: 3.h),
                    Text(p.$2, style: AppText.custom(size: 11, weight: FontWeight.w500, color: AppColors.textMuted, height: 1.35)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _pricingCard(Product product) {
    // "Unit price ()" is what an empty billing unit produced.
    final unitBare = product.unit.replaceFirst('per ', '');
    final priceLabel = unitBare.isEmpty ? 'Unit price' : 'Unit price ($unitBare)';
    return FinanceCard(
      title: 'Pricing',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MetaRow(label: priceLabel, value: product.price),
          // '—' when the org's Product layout does not expose `tax_rate`: the
          // rate is unknown, and so is everything computed from it.
          MetaRow(label: 'GST rate', value: product.gstKnown ? '${product.gst}%' : '—'),
          MetaRow(
              label: 'GST amount',
              value: product.gstKnown ? product.gstAmt : '—',
              last: true),
          Padding(
            padding: EdgeInsets.only(top: 12.h, bottom: 2.h),
            child: Row(
              children: [
                Text('Gross unit price', style: AppText.custom(size: 14, weight: FontWeight.w800, color: AppColors.textPrimary)),
                const Spacer(),
                Text(product.gstKnown ? product.gross : product.price,
                    style: AppText.custom(size: 17, weight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.3)),
              ],
            ),
          ),
          SizedBox(height: 10.h),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
            decoration: BoxDecoration(color: AppColors.bgScreen, borderRadius: BorderRadius.circular(10.r)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(PhosphorIconsRegular.info, size: 14.sp, color: AppColors.textPlaceholder),
                SizedBox(width: 8.w),
                Expanded(
                  child: Text(
                    'Price changes apply to new quotes only. Existing quotes keep the name and price captured when they were generated.',
                    style: AppText.custom(size: 11.5, weight: FontWeight.w500, color: AppColors.textMuted2, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The row's own description.
  ///
  /// The fallback used to compose a sentence — "<name> delivered by Kairali
  /// Interior Works. Billed <unit> at <price> + 18% GST." — which named the
  /// prototype's vendor and asserted a tax rate, for a product whose
  /// description the backend simply left empty.
  String _desc(Product p) {
    final d = p.desc?.trim();
    return d == null || d.isEmpty ? 'No description added.' : d;
  }

  /// What a package contains and what that comes to (`products.md` §7).
  ///
  /// Every figure here is the server's: components are priced live off the
  /// component products, and `price` is recomputed from this composition on
  /// every write. The app calculates nothing.
  ///
  /// The line items render when the payload carries them; this org's view
  /// settings withhold `components`/`adjustments` while still sending the six
  /// totals, so the card says which part is missing rather than implying an
  /// empty package.
  Widget _compositionCard(PackageComposition c) {
    final hasLines = c.components.isNotEmpty || c.adjustments.isNotEmpty;
    return FinanceCard(
      title: 'Package composition',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final comp in c.components)
            MetaRow(
              label: '${comp.name}${comp.quantity > 1 ? ' × ${comp.quantity}' : ''}',
              value: formatInr(comp.lineExcl),
            ),
          for (final adj in c.adjustments)
            MetaRow(
              label: adj.display,
              value: '${adj.isDiscount ? '−' : ''}${formatInr(adj.amount)}',
            ),
          if (!hasLines)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 4.h),
              child: Text('Component breakdown is not available for this package.',
                  style: AppText.custom(
                      size: 12.5, weight: FontWeight.w500, color: AppColors.textMuted)),
            ),
          MetaRow(label: 'Components subtotal', value: formatInr(c.componentsExcl)),
          if (c.hasAdjustments)
            MetaRow(
                label: 'Adjustments',
                value: '${c.adjustmentsExcl < 0 ? '−' : ''}'
                    '${formatInr(c.adjustmentsExcl.abs())}'),
          MetaRow(label: 'Tax', value: formatInr(c.taxAmount), last: true),
          Padding(
            padding: EdgeInsets.only(top: 12.h, bottom: 2.h),
            child: Row(
              children: [
                Text('Package total',
                    style: AppText.custom(size: 14, weight: FontWeight.w800, color: AppColors.textPrimary)),
                const Spacer(),
                Text(formatInr(c.totalIncl),
                    style: AppText.custom(
                        size: 17, weight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.3)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The overflow menu behind the header's 3-dot button, which used to toast
  /// "Product actions" and do nothing.
  void _openMenu(BuildContext context, WidgetRef ref, Product product) {
    showActionMenu(
      context,
      title: 'Product actions',
      actions: [
        MenuAction(
          icon: PhosphorIconsRegular.power,
          label: product.active ? 'Deactivate' : 'Activate',
          onTap: () => _setActive(ref, product, !product.active),
        ),
        MenuAction(
          icon: PhosphorIconsRegular.trash,
          label: 'Delete product',
          destructive: true,
          onTap: () => _confirmDelete(context, ref, product),
        ),
      ],
    );
  }

  /// `DELETE /crm/products/{id}/` (`products.md` §4), behind a confirmation —
  /// it is a hard delete, not an archive.
  ///
  /// The backend refuses (`400`) when the product is a component of a package,
  /// naming the packages; that message is shown as-is rather than replaced with
  /// a generic failure. A product merely referenced by leads or customers does
  /// delete — those FKs are `SET_NULL`.
  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, Product product) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
        title: Text('Delete this product?',
            style: AppText.custom(size: 17, weight: FontWeight.w800, color: AppColors.textPrimary)),
        content: Text(
            '"${product.name}" will be removed from the catalog. Quotes already '
            'issued keep the name and price they captured.',
            style: AppText.body(color: AppColors.textMuted)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('Cancel', style: AppText.bodyStrong(color: AppColors.textLabelAlt))),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text('Delete', style: AppText.bodyStrong(color: AppColors.error))),
        ],
      ),
    );
    if (go != true) return;
    if (!ApiConfig.apiEnabled) {
      ref.read(toastProvider.notifier).show('Product deleted');
      return;
    }
    try {
      await ref.read(productsRepositoryProvider).deleteProduct(product.id);
      ref.invalidate(productsProvider);
      ref.read(toastProvider.notifier).show('Product deleted');
      // The record is gone; staying on its detail screen would show a husk.
      if (context.mounted) context.pop();
    } on AppError catch (e) {
      ref.read(toastProvider.notifier).showError(e.message);
    }
  }

  /// The catalog item's audit trail, under the Notes card.
  ///
  /// `products.md` has no per-product feed, so this is the shared
  /// `/access-control/audit-logs/` trail keyed by `model_name=Product` — the
  /// same one the lead, customer and quote detail pages use.
  ///
  /// The card stays on screen when the trail is empty, saying so.
  ///
  /// Hiding it read as "the feature is missing": most of this catalog predates
  /// the audit hook (the seeded rows have no trail at all), and a role without
  /// `view_audit_log` gets a 403 that resolves to the same empty list. The
  /// wording claims neither — it says only that there is nothing to show.
  Widget _activityCard(WidgetRef ref, String id) {
    final entries = ref.watch(productActivityLogProvider(id)).valueOrNull ?? const [];
    return FinanceCard(
      title: 'Activity',
      child: Padding(
        padding: EdgeInsets.only(top: 6.h),
        child: entries.isEmpty
            ? Text('No activity to show for this item.',
                style: AppText.custom(
                    size: 13, weight: FontWeight.w500, color: AppColors.textMuted))
            : ActivityTimeline(entries: [for (final e in entries) _auditRow(e)]),
      ),
    );
  }

  /// One audit row as a timeline entry, iconed by what kind of event it was.
  ActivityEntry _auditRow(AuditEntry e) {
    final (icon, tone, bg) = switch (e.kind) {
      AuditEventKind.created => (PhosphorIconsRegular.package, AppColors.blueBright, AppColors.tintBlue),
      AuditEventKind.statusChanged => (PhosphorIconsRegular.arrowsClockwise, AppColors.warning, AppColors.tintAmber),
      AuditEventKind.noteAdded => (PhosphorIconsRegular.note, AppColors.pending, AppColors.tintPurple),
      AuditEventKind.childAdded => (PhosphorIconsRegular.plusCircle, AppColors.success, AppColors.tintGreen),
      AuditEventKind.deleted => (PhosphorIconsRegular.trash, AppColors.error, AppColors.tintRed),
      _ => (PhosphorIconsRegular.pencilSimple, AppColors.blueBright, AppColors.tintBlue),
    };
    // Actor and "2h ago" share the single sub-line the timeline gives a row.
    final when = e.at == null ? '' : relativeTime(e.at);
    final sub = [e.subtitle, e.actor, when].where((s) => s.isNotEmpty).join(' · ');
    return ActivityEntry(icon: icon, tone: tone, bg: bg, title: e.title, sub: sub);
  }

  /// Flips `is_active` (`PATCH /crm/products/{id}/`, `products.md` §4).
  ///
  /// The button used to toast "Product deactivated" without a write, so the
  /// pill it claimed to change was back to Active on the next read.
  Future<void> _setActive(WidgetRef ref, Product product, bool active) async {
    if (!ApiConfig.apiEnabled) {
      ref.read(toastProvider.notifier)
          .show(active ? 'Product activated' : 'Product deactivated');
      return;
    }
    try {
      await ref
          .read(productsRepositoryProvider)
          .updateProduct(product.id, {'is_active': active});
      ref.invalidate(productDetailProvider(product.id));
      ref.invalidate(productsProvider);
      ref.read(toastProvider.notifier)
          .show(active ? 'Product activated' : 'Product deactivated');
    } on AppError catch (e) {
      ref.read(toastProvider.notifier).showError(e.message);
    }
  }

  /// Posts an internal note against the product
  /// (`/crm/notes/` with `related_to=product`, verified live).
  ///
  /// The composer used to toast "Note added" and post nothing, so the note
  /// vanished the moment the card reloaded.
  Future<void> _addNote(WidgetRef ref, String id, String body) async {
    final text = body.trim();
    if (text.isEmpty) return;
    if (!ApiConfig.apiEnabled) {
      ref.read(toastProvider.notifier).show('Note added');
      return;
    }
    try {
      await ref.read(notesRepositoryProvider).addNote(
            relatedTo: 'product',
            relatedToId: id,
            body: text,
          );
      ref.invalidate(productNotesProvider(id));
      ref.read(toastProvider.notifier).show('Note added');
    } on AppError catch (e) {
      ref.read(toastProvider.notifier).showError(e.message);
    }
  }

  static String _orDash(String v) => v.isEmpty ? '—' : v;

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
  }
}
