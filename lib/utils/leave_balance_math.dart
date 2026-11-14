import '../models/leave_store.dart';

/// What an employee can still take from each bucket, as the apply-leave
/// form shows it: leave_balance()'s usable figure, less this person's own
/// requests the balance has not counted yet.
///
/// leave_balance() counts approved leave only once its first day has
/// arrived, and never counts pending requests. Without taking those off, a
/// second request could be told it was paid when the first had already
/// used the days; without trusting leave_balance() (the old estimate of one
/// CL and one ML per cycle), someone with days carried forward was warned
/// their leave would be unpaid. That is how Jose was shown an LOP warning.
///
/// Each outstanding request takes off its paid days only: leave_balance()
/// charges a bucket with days less LOP, so taking off the LOP part too
/// would make a request look as if it used more than it will.
///
/// [usable] maps bucket ('CL', 'ML', 'EL') to leave_balance().usable.
/// Buckets not in [usable] are ignored. Results never go below zero.
Map<String, double> usableAfterOutstanding({
  required Map<String, double> usable,
  required Iterable<LeaveApplication> myLeaves,
  required DateTime today,
}) {
  final result = Map<String, double>.of(usable);
  final day = DateTime(today.year, today.month, today.day);
  for (final a in myLeaves) {
    final pending = a.managerStatus == LeaveApprovalStatus.pending;
    final upcoming = a.managerStatus == LeaveApprovalStatus.approved && a.from.isAfter(day);
    if (!pending && !upcoming) continue;
    final b = a.bucket;
    if (result.containsKey(b)) {
      result[b] = (result[b]! - a.paidDays).clamp(0.0, 9999.0).toDouble();
    }
  }
  return result;
}
