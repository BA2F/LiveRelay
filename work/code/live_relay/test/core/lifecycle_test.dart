import 'package:flutter_test/flutter_test.dart';
import 'package:live_relay/core/domain/entities.dart';
import 'package:live_relay/core/domain/lifecycle.dart';

void main() {
  const machine = LifeStateMachine();

  test('allows temporary incapacity and recovery', () {
    expect(
      machine.canTransition(LifeState.active, LifeState.incapacitated),
      isTrue,
    );
    expect(
      machine.canTransition(LifeState.incapacitated, LifeState.active),
      isTrue,
    );
  });

  test('deceased is terminal outside explicit demo reset', () {
    expect(
      machine.canTransition(LifeState.deceased, LifeState.active),
      isFalse,
    );
    expect(
      () => machine.validate(LifeState.deceased, LifeState.active),
      throwsA(isA<InvalidLifeStateTransition>()),
    );
  });
}
