/// Replaces Supabase RealtimeChannel for poll/stream subscriptions.
class SubscriptionHandle {
  SubscriptionHandle(this.cancel);
  final void Function() cancel;
}
