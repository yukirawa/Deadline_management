const { DateTime } = require('luxon');

const DEFAULT_TIMEZONE = 'Asia/Tokyo';
const FALLBACK_DUE_TIME = '23:59';
const MAX_NOTIFICATION_RULES_PER_TYPE = 5;
const DEFAULT_DEADLINE_REMINDER_RULES = Object.freeze([
  Object.freeze({
    id: 'deadline-24h',
    offsetMinutes: 24 * 60,
    enabled: true,
  }),
  Object.freeze({
    id: 'deadline-2h',
    offsetMinutes: 2 * 60,
    enabled: true,
  }),
]);

function cloneDeadlineRule(rule) {
  return {
    id: rule.id,
    offsetMinutes: rule.offsetMinutes,
    enabled: rule.enabled,
  };
}

function cloneDailyRule(rule) {
  return {
    id: rule.id,
    time: rule.time,
    weekdays: [...rule.weekdays],
    enabled: rule.enabled,
  };
}

function isValidQuarterHourValue(value) {
  return Number.isInteger(value) && value >= 0 && value % 15 === 0;
}

function isValidQuarterHourTime(value) {
  if (typeof value !== 'string') {
    return false;
  }
  const match = /^(\d{2}):(\d{2})$/.exec(value);
  if (!match) {
    return false;
  }
  const hour = Number.parseInt(match[1], 10);
  const minute = Number.parseInt(match[2], 10);
  return hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59 && minute % 15 === 0;
}

function normalizeDeadlineReminderRules(rawRules) {
  if (!Array.isArray(rawRules)) {
    return DEFAULT_DEADLINE_REMINDER_RULES.map(cloneDeadlineRule);
  }

  const normalized = [];
  const offsets = new Set();

  for (const item of rawRules) {
    if (!item || typeof item !== 'object') {
      continue;
    }

    const id = typeof item.id === 'string' && item.id.length > 0 ? item.id : null;
    const offsetMinutes = Number.isFinite(item.offsetMinutes) ? Number(item.offsetMinutes) : NaN;
    const enabled = typeof item.enabled === 'boolean' ? item.enabled : true;

    if (!id || !isValidQuarterHourValue(offsetMinutes) || offsets.has(offsetMinutes)) {
      continue;
    }

    offsets.add(offsetMinutes);
    normalized.push({ id, offsetMinutes, enabled });
    if (normalized.length >= MAX_NOTIFICATION_RULES_PER_TYPE) {
      break;
    }
  }

  return normalized;
}

function normalizeDailySummaryRules(rawRules) {
  if (!Array.isArray(rawRules)) {
    return [];
  }

  const normalized = [];
  const times = new Set();

  for (const item of rawRules) {
    if (!item || typeof item !== 'object') {
      continue;
    }

    const id = typeof item.id === 'string' && item.id.length > 0 ? item.id : null;
    const time = typeof item.time === 'string' ? item.time : '';
    const weekdays = Array.isArray(item.weekdays)
      ? [...new Set(item.weekdays.map((value) => Number.parseInt(value, 10)).filter((value) => value >= 1 && value <= 7))].sort(
          (left, right) => left - right,
        )
      : [];
    const enabled = typeof item.enabled === 'boolean' ? item.enabled : true;

    if (!id || !isValidQuarterHourTime(time) || weekdays.length === 0 || times.has(time)) {
      continue;
    }

    times.add(time);
    normalized.push({ id, time, weekdays, enabled });
    if (normalized.length >= MAX_NOTIFICATION_RULES_PER_TYPE) {
      break;
    }
  }

  return normalized;
}

function normalizeProfile(profile) {
  const source = profile && typeof profile === 'object' ? profile : {};
  return {
    notificationsEnabled: Boolean(source.notificationsEnabled),
    timezone: typeof source.timezone === 'string' ? source.timezone : DEFAULT_TIMEZONE,
    deadlineReminderRules: normalizeDeadlineReminderRules(source.deadlineReminderRules),
    dailySummaryRules: normalizeDailySummaryRules(source.dailySummaryRules),
  };
}

function resolveSlotWindow(nowUtc, timezone) {
  const localNow = nowUtc.setZone(timezone);
  if (!localNow.isValid) {
    return null;
  }

  const flooredMinute = localNow.minute - (localNow.minute % 15);
  const slotStart = localNow.set({
    minute: flooredMinute,
    second: 0,
    millisecond: 0,
  });

  return {
    slotStart,
    previousSlotStart: slotStart.minus({ minutes: 15 }),
    todayDate: slotStart.toFormat('yyyy-MM-dd'),
    tomorrowDate: slotStart.plus({ days: 1 }).toFormat('yyyy-MM-dd'),
  };
}

function resolveDueDailySummaryRules(rules, slotStart) {
  const slotTime = slotStart.toFormat('HH:mm');
  return rules.filter((rule) => rule.enabled && rule.time === slotTime && rule.weekdays.includes(slotStart.weekday));
}

function normalizeDueTime(dueTime) {
  if (!isValidQuarterHourTime(dueTime)) {
    return FALLBACK_DUE_TIME;
  }
  return dueTime;
}

function resolveTaskDueDateTime(task, timezone) {
  const dueDate = typeof task.dueDate === 'string' ? task.dueDate : '';
  if (!/^\d{4}-\d{2}-\d{2}$/.test(dueDate)) {
    return null;
  }

  const dueTime = normalizeDueTime(task.dueTime);
  const dueDateTime = DateTime.fromFormat(`${dueDate} ${dueTime}`, 'yyyy-MM-dd HH:mm', {
    zone: timezone,
  });

  if (!dueDateTime.isValid) {
    return null;
  }
  return dueDateTime;
}

function selectTasksForDeadlineRule(taskDocs, rule, slotWindow, timezone) {
  const matched = [];

  for (const taskDoc of taskDocs) {
    const task = typeof taskDoc.data === 'function' ? taskDoc.data() : taskDoc;
    const dueDateTime = resolveTaskDueDateTime(task, timezone);
    if (!dueDateTime) {
      continue;
    }

    const targetTime = dueDateTime.minus({ minutes: rule.offsetMinutes });
    const targetMillis = targetTime.toMillis();
    if (
      targetMillis > slotWindow.previousSlotStart.toMillis() &&
      targetMillis <= slotWindow.slotStart.toMillis()
    ) {
      matched.push(taskDoc);
    }
  }

  return matched;
}

function buildSummary(taskDocs, todayDate, tomorrowDate) {
  let total = 0;
  let overdue = 0;
  let today = 0;
  let tomorrow = 0;

  for (const taskDoc of taskDocs) {
    const task = typeof taskDoc.data === 'function' ? taskDoc.data() : taskDoc;
    const dueDate = task.dueDate;
    if (typeof dueDate !== 'string' || dueDate.length !== 10) {
      continue;
    }

    total += 1;
    if (dueDate < todayDate) {
      overdue += 1;
    } else if (dueDate === todayDate) {
      today += 1;
    } else if (dueDate === tomorrowDate) {
      tomorrow += 1;
    }
  }

  return { total, overdue, today, tomorrow };
}

function buildDailySummaryNotification(summary) {
  return {
    title: '締切レーダー',
    body: `未完了${summary.total}件（期限切れ${summary.overdue} / 今日${summary.today} / 明日${summary.tomorrow}）`,
  };
}

function buildDeadlineReminderNotification(taskDocs, rule) {
  const taskTitles = taskDocs
    .map((taskDoc) => (typeof taskDoc.data === 'function' ? taskDoc.data() : taskDoc))
    .map((task) => task.title)
    .filter((value) => typeof value === 'string' && value.length > 0);
  const head = taskTitles.slice(0, 2).join(' / ');
  const suffix = taskTitles.length > 2 ? ' ほか' : '';

  return {
    title: '締切リマインド',
    body:
      taskTitles.length === 0
        ? `${formatOffsetLabel(rule.offsetMinutes)}の締切が${taskDocs.length}件あります`
        : `${formatOffsetLabel(rule.offsetMinutes)}の締切が${taskDocs.length}件あります: ${head}${suffix}`,
  };
}

function formatOffsetLabel(offsetMinutes) {
  const days = Math.floor(offsetMinutes / (24 * 60));
  const remainingAfterDays = offsetMinutes % (24 * 60);
  const hours = Math.floor(remainingAfterDays / 60);
  const minutes = remainingAfterDays % 60;
  const segments = [];

  if (days > 0) {
    segments.push(`${days}日`);
  }
  if (hours > 0) {
    segments.push(`${hours}時間`);
  }
  if (minutes > 0) {
    segments.push(`${minutes}分`);
  }

  if (segments.length === 0) {
    return '期限ちょうど';
  }
  return `${segments.join(' ')}前`;
}

function sanitizeKeyPart(value) {
  return String(value).replace(/[^A-Za-z0-9_-]/g, '_');
}

function buildNotificationSlotKey({ mode, ruleId, slotStart, timezone }) {
  return `${mode}_${sanitizeKeyPart(ruleId)}_${slotStart.toFormat('yyyy-MM-dd_HHmm')}_${sanitizeKeyPart(timezone)}`;
}

module.exports = {
  DEFAULT_TIMEZONE,
  FALLBACK_DUE_TIME,
  buildDailySummaryNotification,
  buildDeadlineReminderNotification,
  buildNotificationSlotKey,
  buildSummary,
  formatOffsetLabel,
  normalizeProfile,
  resolveDueDailySummaryRules,
  resolveSlotWindow,
  resolveTaskDueDateTime,
  selectTasksForDeadlineRule,
};
