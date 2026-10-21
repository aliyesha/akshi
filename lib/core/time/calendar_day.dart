/// Returns the number of local calendar-date boundaries from [from] to [to].
///
/// Expiry labels and warning thresholds describe civil days, not elapsed
/// 24-hour periods. Converting both instants to local date components and then
/// comparing UTC anchors keeps the result stable across daylight-saving
/// transitions, where adjacent local dates can be 23 or 25 hours apart.
int localCalendarDayDifference({
  required DateTime from,
  required DateTime to,
}) => calendarDayDifference(from: from.toLocal(), to: to.toLocal());

/// Returns the number of calendar-date boundaries between two values whose
/// date components already belong to the intended civil time zone.
///
/// This lower-level form accepts `TZDateTime` values in tests and in any future
/// named-zone presentation without converting them to the host system zone.
int calendarDayDifference({required DateTime from, required DateTime to}) {
  final fromDate = DateTime.utc(from.year, from.month, from.day);
  final toDate = DateTime.utc(to.year, to.month, to.day);
  return toDate.difference(fromDate).inDays;
}
