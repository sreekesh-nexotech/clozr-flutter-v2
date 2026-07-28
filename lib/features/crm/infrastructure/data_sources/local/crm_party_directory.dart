/// Minimal identity directory (id → name + company) for the customers and leads
/// referenced by quotes, payments and invoices. Ported from the prototype's
/// `customersRaw` / `raw` seeds so the finance screens can resolve a `custId` /
/// `leadId` to a display name without depending on the (separately-owned)
/// customers feature. When the API lands this is replaced by a `/customers`
/// lookup; the finance VMs read it exactly as-is.
class CrmParty {
  final String id;
  final String name;
  final String company;
  const CrmParty(this.id, this.name, this.company);

  /// "Company · Name" — the one-line label used across finance cards.
  String get who => '$company · $name';
}

class CrmPartyDirectory {
  CrmPartyDirectory._();

  static const Map<String, CrmParty> _customers = {
    'C2001': CrmParty('C2001', 'Ramesh Pillai', 'Kalyan Silks'),
    'C2002': CrmParty('C2002', 'Aboobacker Haji', 'Lulu Fashion Store'),
    'C2003': CrmParty('C2003', 'Jose Kuriakose', 'Marari Sands Resort'),
    'C2004': CrmParty('C2004', 'Nikhil Menon', 'Taj Gateway Annexe'),
    'C2005': CrmParty('C2005', 'Priya Varma', 'Aster Medcity OPD'),
    'C2006': CrmParty('C2006', 'Suresh Nair', 'KIMS Clinic'),
    'C2007': CrmParty('C2007', 'Biju Thomas', 'Federal Bank Aluva'),
    'C2008': CrmParty('C2008', 'Anand Krishnan', 'Infopark Tower B'),
    'C2009': CrmParty('C2009', 'Geetha Mohan', 'Technopark Tejaswini'),
    'C2010': CrmParty('C2010', 'Ashraf Ali', 'Malabar Gold Showroom'),
    'C2011': CrmParty('C2011', 'Mathew George', 'Nirapara Supermarket'),
    'C2012': CrmParty('C2012', 'Devika Iyer', 'Paragon Restaurant'),
    'C2013': CrmParty('C2013', 'Hari Prasad', 'Orbit Health'),
  };

  static const Map<String, CrmParty> _leads = {
    'L1010': CrmParty('L1010', 'Sangeeth Raj', 'Workafella Coworking'),
  };

  static CrmParty? customer(String? id) => id == null ? null : _customers[id];
  static CrmParty? lead(String? id) => id == null ? null : _leads[id];

  /// Resolve the best party for an entity that may link to either a customer or
  /// a lead (customer wins, matching the prototype).
  static CrmParty? resolve({String? custId, String? leadId}) =>
      customer(custId) ?? lead(leadId);
}
