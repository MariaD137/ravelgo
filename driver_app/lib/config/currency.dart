import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Central currency configuration for the driver app.
///
/// Defaults to the Nigerian Naira, but the symbol and ISO code can be
/// overridden per deployment via .env (CURRENCY_SYMBOL / CURRENCY_CODE) so the
/// same codebase can serve new countries as RavelGo expands — change the two
/// env values, rebuild, and every price in the app follows.
class Currency {
  static String get symbol {
    try {
      final s = (dotenv.env['CURRENCY_SYMBOL'] ?? '').trim();
      return s.isNotEmpty ? s : '₦';
    } catch (_) {
      return '₦';
    }
  }

  static String get code {
    try {
      final c = (dotenv.env['CURRENCY_CODE'] ?? '').trim();
      return c.isNotEmpty ? c : 'NGN';
    } catch (_) {
      return 'NGN';
    }
  }

  /// Format an amount with the active symbol and thousands separators,
  /// e.g. 5000 -> "₦5,000.00" (or "₦5,000" with decimals: 0).
  static String format(num amount, {int decimals = 2}) {
    final fixed = amount.toStringAsFixed(decimals);
    final dot = fixed.indexOf('.');
    final intPart = dot == -1 ? fixed : fixed.substring(0, dot);
    final fracPart = dot == -1 ? '' : fixed.substring(dot + 1);

    final neg = intPart.startsWith('-');
    final digits = neg ? intPart.substring(1) : intPart;
    final buf = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
      buf.write(digits[i]);
    }
    final grouped = '${neg ? '-' : ''}$buf';
    return decimals > 0 ? '$symbol$grouped.$fracPart' : '$symbol$grouped';
  }
}
