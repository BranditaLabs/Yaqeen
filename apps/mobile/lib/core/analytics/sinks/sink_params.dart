import '../analytics.dart';

/// What a sink may forward to its SDK: the allowlisted params only. `att` is a control flag from
/// [Analytics], never an event parameter.
Map<String, Object> forwardableParams(Map<String, Object> params) => {
      for (final e in params.entries)
        if (e.key != 'att' && Analytics.allowedParams.contains(e.key)) e.key: e.value,
    };

/// The `att` flag [Analytics] attaches to every event (1 = ATT authorized / not iOS).
bool attFrom(Map<String, Object> params) => params['att'] == 1;

/// `purchase` needs both a numeric value and a currency; anything else is dropped.
({double value, String currency})? purchaseOf(Map<String, Object> params) {
  final value = params['value'];
  final currency = params['currency'];
  if (value is! num || currency is! String || currency.isEmpty) return null;
  return (value: value.toDouble(), currency: currency);
}
