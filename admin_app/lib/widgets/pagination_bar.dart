import 'package:flutter/material.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';

/// Previous / next controls plus "Page X of Y · N total" for every paged
/// admin list. Hidden entirely when there is only one page and nothing to
/// navigate, so short lists look exactly as they did before pagination.
class PaginationBar extends StatelessWidget {
  final int page;
  final int totalPages;
  final int total;
  final bool busy;
  final ValueChanged<int> onPageChanged;
  final String itemLabel;

  const PaginationBar({
    super.key,
    required this.page,
    required this.totalPages,
    required this.total,
    required this.onPageChanged,
    this.busy = false,
    this.itemLabel = 'total',
  });

  @override
  Widget build(BuildContext context) {
    if (totalPages <= 1 && total <= 0) return const SizedBox.shrink();
    final canPrev = !busy && page > 1;
    final canNext = !busy && page < totalPages;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Previous page',
            onPressed: canPrev ? () => onPageChanged(page - 1) : null,
            icon: const Icon(Icons.chevron_left),
            color: AppColors.textPrimary,
          ),
          Expanded(
            child: Text(
              'Page $page of $totalPages  ·  $total $itemLabel',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            tooltip: 'Next page',
            onPressed: canNext ? () => onPageChanged(page + 1) : null,
            icon: const Icon(Icons.chevron_right),
            color: AppColors.textPrimary,
          ),
        ],
      ),
    );
  }
}
