import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sist_flutter/scan_api_client.dart';
import 'package:sist_flutter/main.dart';

void main() {
  testWidgets('sample passport can be saved into binder collections', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ShouldISlabThisApp(
        samplePassportLoader: () async => CardPassport.sample(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Should I Slab This'), findsOneWidget);
    expect(find.text('Tap to scan'), findsOneWidget);
    expect(find.text('See a Sample Passport'), findsOneWidget);

    await tester.tap(find.text('See a Sample Passport'));
    await tester.pumpAndSettle();

    expect(find.text('Pikachu ex - 277/217'), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);
    expect(find.text('Add to Binder'), findsOneWidget);

    await tester.tap(find.text('Add to Binder').last);
    await tester.pumpAndSettle();

    expect(find.text('Wishlist'), findsOneWidget);

    await tester.tap(find.text('Wishlist').last);
    await tester.pumpAndSettle();

    expect(find.text('Added to Binder'), findsOneWidget);

    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Binder'));
    await tester.pumpAndSettle();

    expect(find.text('Collections'), findsOneWidget);
    expect(find.text('All Cards'), findsOneWidget);
    expect(find.text('Wishlist'), findsOneWidget);
    expect(find.text('Pikachu ex - 277/217'), findsOneWidget);

    await tester.tap(find.text('Wishlist').first);
    await tester.pumpAndSettle();

    expect(find.text('1 card'), findsWidgets);
    expect(find.text('Pikachu ex - 277/217'), findsWidgets);
  });

  testWidgets('lookup cards show scan action without passport metrics', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final binderStore = BinderStore();
    addTearDown(binderStore.dispose);
    final now = DateTime(2026, 6, 6);
    final lookup = CardPassport(
      id: 'tcg-590027',
      recordType: CardRecordType.lookup,
      externalApiId: '590027',
      productId: 590027,
      name: 'Pikachu ex - 238/191',
      set: 'SV08: Surging Sparks',
      number: '238/191',
      year: '2024',
      marketValue: r'$337.11 market',
      rarity: 'Special Illustration Rare',
      source: 'Live TCG Tracking',
      marketSubtype: 'Holofoil',
      condition: const CardCondition(grade: 'TBD', label: 'Needs scan'),
      centering: const CardCentering(
        topBottom: '--',
        leftRight: '--',
        tilt: '--',
      ),
      createdAt: now,
      updatedAt: now,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PassportSheet(
            passport: lookup,
            binderStore: binderStore,
            scanClient: BackendScanClient(),
            onScan: ({sourceLookup}) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pikachu ex - 238/191'), findsOneWidget);
    expect(find.text('Scan'), findsOneWidget);
    expect(find.text('Add to Binder'), findsOneWidget);
    expect(find.text('Share'), findsNothing);
    expect(find.text('Condition'), findsNothing);
    expect(find.text('Centering'), findsNothing);
    expect(find.text('TBD · Needs scan'), findsNothing);
  });
}
