import 'package:intl/intl.dart';

const String storageDatePattern = 'yyyy-MM-dd';
const String displayDatePattern = 'yyyy/MM/dd';

final DateFormat _storageDateFormatter = DateFormat(storageDatePattern);
final DateFormat _displayDateFormatter = DateFormat(displayDatePattern);

enum RiskLevel { expired, danger, warning, safe }

DateTime parseStorageDate(String value) {
  final parsed = _storageDateFormatter.parseStrict(value);
  return DateTime(parsed.year, parsed.month, parsed.day);
}

String formatStorageDate(DateTime date) {
  final normalized = DateTime(date.year, date.month, date.day);
  return _storageDateFormatter.format(normalized);
}

String formatDisplayDate(String dueDate) {
  return _displayDateFormatter.format(parseStorageDate(dueDate));
}

int calculateDaysLeft(String dueDate, {DateTime? now}) {
  final due = parseStorageDate(dueDate);
  final current = now ?? DateTime.now();
  final today = DateTime(current.year, current.month, current.day);
  return due.difference(today).inDays;
}

RiskLevel calculateRiskLevel(int daysLeft) {
  if (daysLeft < 0) {
    return RiskLevel.expired;
  }
  if (daysLeft <= 1) {
    return RiskLevel.danger;
  }
  if (daysLeft <= 3) {
    return RiskLevel.warning;
  }
  return RiskLevel.safe;
}

String riskLabel(RiskLevel riskLevel) {
  switch (riskLevel) {
    case RiskLevel.expired:
      return '期限切れ';
    case RiskLevel.danger:
      return '危険';
    case RiskLevel.warning:
      return '注意';
    case RiskLevel.safe:
      return '余裕';
  }
}

String remainingDaysLabel(int daysLeft) {
  if (daysLeft < 0) {
    return '期限切れ';
  }
  if (daysLeft == 0) {
    return '今日';
  }
  if (daysLeft == 1) {
    return '明日';
  }
  return 'あと$daysLeft日';
}
