/// What a package is made of (`products.md` §7).
///
/// A package is a [Product] with `item_type: "package"`, assembled from
/// component products plus optional adjustments (a discount, a service charge,
/// a margin). Its `price` is **derived**: the backend recomputes it from the
/// composition on every write, so nothing here is a figure the app calculates.
///
/// Plain products carry none of this — the serializer strips `components` and
/// `adjustments` entirely rather than sending empty arrays.
class PackageComposition {
  const PackageComposition({
    this.components = const [],
    this.adjustments = const [],
    required this.componentsExcl,
    required this.componentsIncl,
    required this.adjustmentsExcl,
    required this.adjustmentsIncl,
    required this.totalExcl,
    required this.totalIncl,
  });

  /// The component products. Empty when the org's view settings withhold the
  /// array — the totals still arrive, so "empty" here means "not sent", not
  /// "a package with nothing in it".
  final List<PackageComponent> components;
  final List<PackageAdjustment> adjustments;

  /// The six server-computed totals, in rupees. All arrive as money strings.
  final double componentsExcl;
  final double componentsIncl;
  final double adjustmentsExcl;
  final double adjustmentsIncl;
  final double totalExcl;
  final double totalIncl;

  /// Whether anything adjusts the component subtotal — a package can have none.
  bool get hasAdjustments => adjustmentsExcl != 0 || adjustments.isNotEmpty;

  /// The tax the package attracts, which is the difference the server already
  /// computed rather than a rate the app applies.
  double get taxAmount => totalIncl - totalExcl;
}

/// One component line: a plain product, a quantity, and the line money the
/// server priced **live** off that product (not snapshotted).
class PackageComponent {
  const PackageComponent({
    required this.productId,
    required this.name,
    this.code = '',
    this.billingUnit = '',
    required this.quantity,
    required this.unitPrice,
    required this.lineExcl,
    required this.lineIncl,
  });

  final String productId;
  final String name;
  final String code;
  final String billingUnit;
  final int quantity;
  final double unitPrice;
  final double lineExcl;
  final double lineIncl;
}

/// One adjustment line. `amount` is stored positive and [sign] carries the
/// direction — discounts are `-1` — so the display has to apply it rather than
/// assume a negative number.
class PackageAdjustment {
  const PackageAdjustment({
    required this.type,
    required this.label,
    required this.amount,
    required this.sign,
    required this.amountIncl,
  });

  /// `service_charge` | `margin` | `misc_cost` | `bundle_discount`.
  final String type;
  final String label;
  final double amount;
  final int sign;
  final double amountIncl;

  bool get isDiscount => sign < 0;

  /// The label the row shows, falling back to the type when the package author
  /// left it blank.
  String get display => label.isNotEmpty ? label : _humanType;

  String get _humanType => switch (type) {
        'bundle_discount' => 'Bundle discount',
        'service_charge' => 'Service charge',
        'misc_cost' => 'Miscellaneous',
        'margin' => 'Margin',
        _ => 'Adjustment',
      };
}
