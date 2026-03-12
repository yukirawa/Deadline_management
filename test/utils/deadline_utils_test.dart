import 'package:flutter_test/flutter_test.dart';
import 'package:kigenkanri/utils/deadline_utils.dart';

void main() {
  const baseDate = '2026-03-06';
  final baseNow = DateTime(2026, 3, 6, 18, 0);

  test('daysLeft と危険度の境界値が正しい', () {
    final daysLeftExpired = calculateDaysLeft('2026-03-05', now: baseNow);
    final daysLeftDanger0 = calculateDaysLeft(baseDate, now: baseNow);
    final daysLeftDanger1 = calculateDaysLeft('2026-03-07', now: baseNow);
    final daysLeftWarning2 = calculateDaysLeft('2026-03-08', now: baseNow);
    final daysLeftWarning3 = calculateDaysLeft('2026-03-09', now: baseNow);
    final daysLeftSafe4 = calculateDaysLeft('2026-03-10', now: baseNow);

    expect(daysLeftExpired, -1);
    expect(calculateRiskLevel(daysLeftExpired), RiskLevel.expired);
    expect(calculateRiskLevel(daysLeftDanger0), RiskLevel.danger);
    expect(calculateRiskLevel(daysLeftDanger1), RiskLevel.danger);
    expect(calculateRiskLevel(daysLeftWarning2), RiskLevel.warning);
    expect(calculateRiskLevel(daysLeftWarning3), RiskLevel.warning);
    expect(calculateRiskLevel(daysLeftSafe4), RiskLevel.safe);
  });

  test('残り日数文言が固定仕様どおり', () {
    expect(remainingDaysLabel(-3), '期限切れ');
    expect(remainingDaysLabel(0), '今日');
    expect(remainingDaysLabel(1), '明日');
    expect(remainingDaysLabel(5), 'あと5日');
  });

  test('保存形式と表示形式の日付変換が正しい', () {
    final date = DateTime(2026, 3, 6, 23, 45);

    final stored = formatStorageDate(date);
    final display = formatDisplayDate(stored);

    expect(stored, '2026-03-06');
    expect(display, '2026/03/06');
  });

  test('dueTime が null の場合は 23:59 を使う', () {
    final dueDateTime = resolveDueDateTime('2026-03-06');

    expect(formatStorageTime(dueDateTime), fallbackDueTime);
    expect(dueTimeLabel(null), '時刻未設定');
  });
}
