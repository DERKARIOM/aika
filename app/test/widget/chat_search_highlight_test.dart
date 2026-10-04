import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/pages/chat/chat_search_page.dart';

void main() {
  const style = TextStyle();
  const accent = Colors.red;

  String plain(TextSpan span) => span.toPlainText();

  test('Should highlight the match, case-insensitively', () {
    final span = highlightChatMatch('Le Rapport arrive', 'rapport', style, accent);
    final match = span.children![1] as TextSpan;
    expect(match.text, 'Rapport');
    expect(match.style!.color, accent);
    expect(plain(span), 'Le Rapport arrive');
  });

  test('Should start shortly before a match far in the text', () {
    final text = '${'x' * 100} cible';
    expect(plain(highlightChatMatch(text, 'cible', style, accent)), startsWith('…'));
  });

  test('Should keep the text on one line and plain without a match', () {
    final span = highlightChatMatch('a\nb', 'z', style, accent);
    expect(span.children, isNull);
    expect(span.text, 'a b');
  });
}
