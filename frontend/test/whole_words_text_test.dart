import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:autism_audiobook/widgets/whole_words_text.dart';

void main() {
  testWidgets('shrinks a word that would not fit, so it is never split', (tester) async {
    const style = TextStyle(fontSize: 40);
    await tester.pumpWidget(const MaterialApp(
      home: Center(
        child: SizedBox(
          width: 150,
          child: WholeWordsText('Pengurusan Kandungan', style: style),
        ),
      ),
    ));
    final text = tester.widget<Text>(find.text('Pengurusan Kandungan'));
    final used = text.style!;
    expect(used.fontSize, lessThan(40));
    final widest = WholeWordsText.widestWord(
        'Pengurusan Kandungan', used, TextScaler.noScaling, TextDirection.ltr);
    expect(widest, lessThanOrEqualTo(150));
  });

  testWidgets('leaves text alone when every word fits', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Center(
        child: SizedBox(
          width: 400,
          child: WholeWordsText('Settings', style: TextStyle(fontSize: 28)),
        ),
      ),
    ));
    expect(tester.widget<Text>(find.text('Settings')).style!.fontSize, 28);
  });
}
