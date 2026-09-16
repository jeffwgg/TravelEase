import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression tests for the favorite-removal snackbar.
///
/// Flutter >= 3.35 defaults `SnackBar.persist` to `action != null`
/// (snack_bar.dart: `persist = persist ?? action != null`), so a bar with an
/// Undo action NEVER auto-dismisses unless `persist: false` is set — that was
/// the "popup won't disappear" bug. These tests pin both halves of that
/// behavior on this SDK.
///
/// Mirrors FavoritePhrasesView._onRemove: clearSnackBars() then show, fired in
/// the same frame as a list rebuild. The countdown timer is armed by
/// ScaffoldMessenger on the frame where the entry animation completes, so the
/// pump sequence steps past the 250ms entry before waiting the duration.
void main() {
  Future<void> showBar(
    WidgetTester tester, {
    required bool persistFalse,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => Column(children: [
            const ListTile(title: Text('Where is the gate?')),
            TextButton(
              onPressed: () {
                final messenger = ScaffoldMessenger.of(context);
                messenger.clearSnackBars();
                messenger.showSnackBar(SnackBar(
                  content: const Text('Removed "Where is the gate?" from favorites'),
                  duration: const Duration(seconds: 3),
                  persist: persistFalse ? false : null,
                  action: SnackBarAction(label: 'Undo', onPressed: () {}),
                ));
              },
              child: const Text('remove'),
            ),
          ]),
        ),
      ),
    ));
    await tester.tap(find.text('remove'));
    await tester.pump();                    // bar starts sliding in
    await tester.pump(const Duration(milliseconds: 400)); // entry done -> countdown armed
  }

  testWidgets('persist:false + Undo action auto-dismisses after the duration', (tester) async {
    await showBar(tester, persistFalse: true);
    expect(find.byType(SnackBar), findsOneWidget);

    await tester.pump(const Duration(seconds: 3)); // timeout -> hide begins
    await tester.pumpAndSettle();                  // exit animation
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('without persist:false an action bar STAYS (Flutter >= 3.35 default)', (tester) async {
    await showBar(tester, persistFalse: false);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsOneWidget); // documents the pitfall
  });
}
