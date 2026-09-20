/// One page of an admin list, exactly as the backend's shared pagination
/// contract returns it (backend/src/lib/pagination.ts: `data`, `page`,
/// `pageSize`, `total`, plus the additive `totalPages` / `hasNext`). Every
/// admin list is paged through this rather than fetched "all at once" — the
/// backend caps a page at 100 rows, so anything beyond that was previously
/// simply invisible to reviewers.
class PagedResult<T> {
  final List<T> items;
  final int page;
  final int pageSize;
  final int total;
  final int totalPages;
  final bool hasNext;

  const PagedResult({
    required this.items,
    required this.page,
    required this.pageSize,
    required this.total,
    required this.totalPages,
    required this.hasNext,
  });

  bool get hasPrev => page > 1;

  /// True when this page is empty but the list is not — e.g. the last row on
  /// page 3 was just deleted. The screen should snap back to [totalPages].
  bool get isPastEnd => items.isEmpty && total > 0 && page > totalPages;

  static PagedResult<T> fromJson<T>(Map<String, dynamic> j, T Function(Map<String, dynamic>) mapper) {
    final raw = (j['data'] as List?) ?? const [];
    final page = _i(j['page'], 1);
    final pageSize = _i(j['pageSize'], raw.length);
    final total = _i(j['total'], raw.length);
    // Older backends (or a test double) may omit the additive fields; derive
    // them from the four that always exist so the bar still works.
    final totalPages = j['totalPages'] == null
        ? (pageSize == 0 ? 1 : (total / pageSize).ceil().clamp(1, 1 << 30))
        : _i(j['totalPages'], 1);
    final hasNext = j['hasNext'] is bool ? j['hasNext'] as bool : page < totalPages;
    return PagedResult<T>(
      items: raw.whereType<Map<String, dynamic>>().map(mapper).toList(),
      page: page,
      pageSize: pageSize,
      total: total,
      totalPages: totalPages,
      hasNext: hasNext,
    );
  }

  static int _i(dynamic v, int fallback) => v is num ? v.toInt() : int.tryParse('$v') ?? fallback;
}

/// Page size every admin list asks for. Well under the backend's 100-row
/// ceiling so a page renders quickly, large enough that day-to-day review
/// rarely needs more than a page or two.
const int kAdminPageSize = 50;

/// Builds the `page=..&pageSize=..` query tail, plus any optional filters
/// (null/empty values are omitted). Values are URL-encoded.
String pagedQuery(int page, {int pageSize = kAdminPageSize, Map<String, String?> filters = const {}}) {
  final parts = <String>['page=$page', 'pageSize=$pageSize'];
  filters.forEach((k, v) {
    if (v != null && v.isNotEmpty) parts.add('$k=${Uri.encodeQueryComponent(v)}');
  });
  return parts.join('&');
}
