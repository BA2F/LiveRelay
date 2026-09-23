import 'entities.dart';

class InvalidLifeStateTransition implements Exception {
  const InvalidLifeStateTransition(this.from, this.to);

  final LifeState from;
  final LifeState to;

  @override
  String toString() => '不允许从 ${from.name} 转换到 ${to.name}';
}

/// Pure domain rule. A demo reset is modeled separately so it can never be
/// mistaken for evidence that a deceased owner recovered.
class LifeStateMachine {
  const LifeStateMachine();

  bool canTransition(LifeState from, LifeState to) {
    if (from == to) return false;
    return switch (from) {
      LifeState.active =>
        to == LifeState.incapacitated || to == LifeState.deceased,
      LifeState.incapacitated =>
        to == LifeState.active || to == LifeState.deceased,
      LifeState.deceased => false,
    };
  }

  void validate(LifeState from, LifeState to) {
    if (!canTransition(from, to)) {
      throw InvalidLifeStateTransition(from, to);
    }
  }
}
