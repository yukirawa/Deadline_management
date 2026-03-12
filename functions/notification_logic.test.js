const test = require('node:test');
const assert = require('node:assert/strict');
const { DateTime } = require('luxon');
const {
  buildNotificationSlotKey,
  buildSummary,
  normalizeProfile,
  resolveDueDailySummaryRules,
  resolveSlotWindow,
  resolveTaskDueDateTime,
  selectTasksForDeadlineRule,
} = require('./notification_logic');

function makeDoc(data) {
  return {
    data() {
      return data;
    },
  };
}

test('normalizeProfile fills missing rule arrays with defaults', () => {
  const profile = normalizeProfile({
    notificationsEnabled: true,
    timezone: 'Asia/Tokyo',
  });

  assert.equal(profile.deadlineReminderRules.length, 2);
  assert.deepEqual(profile.dailySummaryRules, []);
});

test('resolveSlotWindow keeps local timezone semantics', () => {
  const slot = resolveSlotWindow(
    DateTime.fromISO('2026-03-12T22:07:00Z'),
    'Asia/Tokyo',
  );

  assert.equal(slot.slotStart.toFormat('yyyy-MM-dd HH:mm'), '2026-03-13 07:00');
  assert.equal(slot.todayDate, '2026-03-13');
});

test('resolveDueDailySummaryRules matches weekday and quarter hour', () => {
  const slotStart = DateTime.fromISO('2026-03-13T07:00:00', {
    zone: 'Asia/Tokyo',
  });

  const matched = resolveDueDailySummaryRules(
    [
      { id: 'daily-a', time: '07:00', weekdays: [1, 5], enabled: true },
      { id: 'daily-b', time: '07:15', weekdays: [5], enabled: true },
      { id: 'daily-c', time: '07:00', weekdays: [6], enabled: true },
    ],
    slotStart,
  );

  assert.deepEqual(
    matched.map((rule) => rule.id),
    ['daily-a'],
  );
});

test('resolveTaskDueDateTime falls back to 23:59 when dueTime is missing', () => {
  const dueDateTime = resolveTaskDueDateTime(
    {
      dueDate: '2026-03-13',
      dueTime: null,
    },
    'Asia/Tokyo',
  );

  assert.equal(dueDateTime.toFormat('HH:mm'), '23:59');
});

test('selectTasksForDeadlineRule matches tasks in the current 15 minute window', () => {
  const slotWindow = resolveSlotWindow(
    DateTime.fromISO('2026-03-13T12:00:00Z'),
    'Asia/Tokyo',
  );

  const matched = selectTasksForDeadlineRule(
    [
      makeDoc({
        title: '2 hours reminder',
        dueDate: '2026-03-13',
        dueTime: '23:00',
      }),
      makeDoc({
        title: 'outside window',
        dueDate: '2026-03-13',
        dueTime: '23:30',
      }),
      makeDoc({
        title: 'fallback time',
        dueDate: '2026-03-14',
        dueTime: null,
      }),
    ],
    { id: 'deadline-2h', offsetMinutes: 120, enabled: true },
    slotWindow,
    'Asia/Tokyo',
  );

  assert.deepEqual(
    matched.map((doc) => doc.data().title),
    ['2 hours reminder'],
  );
});

test('buildSummary aggregates today and tomorrow counts', () => {
  const summary = buildSummary(
    [
      makeDoc({ dueDate: '2026-03-13' }),
      makeDoc({ dueDate: '2026-03-13' }),
      makeDoc({ dueDate: '2026-03-14' }),
      makeDoc({ dueDate: '2026-03-12' }),
    ],
    '2026-03-13',
    '2026-03-14',
  );

  assert.deepEqual(summary, {
    total: 4,
    overdue: 1,
    today: 2,
    tomorrow: 1,
  });
});

test('buildNotificationSlotKey sanitizes timezone and rule id', () => {
  const key = buildNotificationSlotKey({
    mode: 'daily',
    ruleId: '07:00/morning',
    slotStart: DateTime.fromISO('2026-03-13T07:00:00', {
      zone: 'Asia/Tokyo',
    }),
    timezone: 'Asia/Tokyo',
  });

  assert.equal(key, 'daily_07_00_morning_2026-03-13_0700_Asia_Tokyo');
});
