import 'package:flutter_riverpod/flutter_riverpod.dart';

class MyNotifier extends Notifier<int> {
  late String arg;

  @override
  int build() {
    return 0;
  }
}

final myProvider = NotifierProvider.family<MyNotifier, int, String>((String arg) {
  final notifier = MyNotifier();
  notifier.arg = arg;
  return notifier;
});

void main() {}
