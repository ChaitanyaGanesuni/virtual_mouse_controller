/// Spaced repetition: when to show a revision card again.
///
/// The default is the fixed ladder from the design (day 1 → 2 → 4 → 7 → 14 →
/// …). It sits behind [SrsScheduler] so an adaptive scheduler such as FSRS
/// can replace it later; the card already stores what FSRS would need, and
/// every review is logged.
library;

enum Rating {
  again(1),
  hard(2),
  good(3),
  easy(4);

  const Rating(this.value);
  final int value;
}

enum CardType {
  /// "What does this verse teach?"
  meaning,

  /// "Which idea is this verse about?" (answered with its concepts)
  concept,

  /// "How could you apply this today?"
  application;

  static CardType fromWire(String s) => CardType.values.firstWhere((c) => c.name == s);
}

/// The scheduling state of one card.
class CardSchedule {
  const CardSchedule({
    required this.step,
    required this.dueAt,
    this.state = 'new',
    this.reps = 0,
    this.lapses = 0,
    this.lastReviewedAt,
  });

  final int step;
  final DateTime dueAt;
  final String state;
  final int reps;
  final int lapses;
  final DateTime? lastReviewedAt;
}

abstract interface class SrsScheduler {
  /// A new card: when it is first due.
  CardSchedule start(DateTime now);

  CardSchedule review(CardSchedule card, Rating rating, DateTime now);

  /// For the buttons: the wait after each rating ("4 days").
  Duration preview(CardSchedule card, Rating rating, DateTime now);
}

class LadderScheduler implements SrsScheduler {
  const LadderScheduler({this.days = defaultLadder});

  /// Days until the next review at each step.
  static const defaultLadder = [1, 2, 4, 7, 14, 30, 60, 120, 240];

  /// "Again" shows the card again later in the same session.
  static const relearnDelay = Duration(minutes: 10);

  final List<int> days;

  int _clamp(int step) => step.clamp(0, days.length - 1);

  @override
  CardSchedule start(DateTime now) => CardSchedule(step: 0, dueAt: now.add(Duration(days: days.first)));

  @override
  CardSchedule review(CardSchedule card, Rating rating, DateTime now) {
    final (step, due, state) = switch (rating) {
      // Forgotten: back to the bottom of the ladder.
      Rating.again => (0, now.add(relearnDelay), 'relearning'),
      // Remembered with effort: repeat the current interval.
      Rating.hard => (card.step, now.add(Duration(days: days[_clamp(card.step)])), 'review'),
      Rating.good => (_clamp(card.step + 1), now.add(Duration(days: days[_clamp(card.step + 1)])), 'review'),
      Rating.easy => (_clamp(card.step + 2), now.add(Duration(days: days[_clamp(card.step + 2)])), 'review'),
    };
    return CardSchedule(
      step: step,
      dueAt: due,
      state: state,
      reps: card.reps + 1,
      lapses: card.lapses + (rating == Rating.again && card.reps > 0 ? 1 : 0),
      lastReviewedAt: now,
    );
  }

  @override
  Duration preview(CardSchedule card, Rating rating, DateTime now) =>
      review(card, rating, now).dueAt.difference(now);
}
