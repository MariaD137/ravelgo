const _months = [
  "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
];

String formatFriendlyDate(DateTime date) {
  final hour12 = date.hour % 12 == 0 ? 12 : date.hour % 12;
  final period = date.hour >= 12 ? "PM" : "AM";
  final minute = date.minute.toString().padLeft(2, '0');
  return "${_months[date.month - 1]} ${date.day}, $hour12:$minute $period";
}

String formatShortDate(DateTime date) => "${_months[date.month - 1]} ${date.day}, ${date.year}";
