const { DateTime } = require('luxon');
const admin = require('firebase-admin');
const { logger } = require('firebase-functions');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const {
  buildDailySummaryNotification,
  buildDeadlineReminderNotification,
  buildNotificationSlotKey,
  buildSummary,
  normalizeProfile,
  resolveDueDailySummaryRules,
  resolveSlotWindow,
  selectTasksForDeadlineRule,
} = require('./notification_logic');

admin.initializeApp();

const db = admin.firestore();
const REGION = 'asia-northeast1';

exports.sendDeadlineSummary = onSchedule(
  {
    region: REGION,
    schedule: 'every 15 minutes',
    timeZone: 'Etc/UTC',
    memory: '256MiB',
  },
  async () => {
    const usersSnapshot = await db.collection('users').get();
    const nowUtc = DateTime.utc();

    for (const userDoc of usersSnapshot.docs) {
      try {
        await processUser(userDoc.id, nowUtc);
      } catch (error) {
        logger.error('Failed to process user notification', {
          uid: userDoc.id,
          error: String(error),
        });
      }
    }
  },
);

async function processUser(uid, nowUtc) {
  const profileRef = db.collection('users').doc(uid).collection('settings').doc('profile');
  const profileSnapshot = await profileRef.get();
  if (!profileSnapshot.exists) {
    return;
  }

  const profile = normalizeProfile(profileSnapshot.data());
  if (!profile.notificationsEnabled) {
    return;
  }

  const slotWindow = resolveSlotWindow(nowUtc, profile.timezone);
  if (!slotWindow) {
    return;
  }

  const dueDailyRules = resolveDueDailySummaryRules(profile.dailySummaryRules, slotWindow.slotStart);
  const enabledDeadlineRules = profile.deadlineReminderRules.filter((rule) => rule.enabled);

  if (dueDailyRules.length === 0 && enabledDeadlineRules.length === 0) {
    return;
  }

  let tasksSnapshotPromise;
  let devicesSnapshotPromise;

  const getTasksSnapshot = async () => {
    tasksSnapshotPromise ??= db
      .collection('users')
      .doc(uid)
      .collection('tasks')
      .where('isDeleted', '==', false)
      .where('done', '==', false)
      .get();
    return tasksSnapshotPromise;
  };

  const getDevicesSnapshot = async () => {
    devicesSnapshotPromise ??= db.collection('users').doc(uid).collection('devices').get();
    return devicesSnapshotPromise;
  };

  for (const rule of dueDailyRules) {
    await processDailySummaryRule({
      uid,
      timezone: profile.timezone,
      slotWindow,
      rule,
      getTasksSnapshot,
      getDevicesSnapshot,
    });
  }

  if (enabledDeadlineRules.length === 0) {
    return;
  }

  const tasksSnapshot = await getTasksSnapshot();
  for (const rule of enabledDeadlineRules) {
    const matchedTasks = selectTasksForDeadlineRule(
      tasksSnapshot.docs,
      rule,
      slotWindow,
      profile.timezone,
    );
    if (matchedTasks.length === 0) {
      continue;
    }

    await processDeadlineReminderRule({
      uid,
      timezone: profile.timezone,
      slotWindow,
      rule,
      matchedTasks,
      getDevicesSnapshot,
    });
  }
}

async function processDailySummaryRule({
  uid,
  timezone,
  slotWindow,
  rule,
  getTasksSnapshot,
  getDevicesSnapshot,
}) {
  const slotKey = buildNotificationSlotKey({
    mode: 'daily',
    ruleId: rule.id,
    slotStart: slotWindow.slotStart,
    timezone,
  });
  const slotRef = db.collection('users').doc(uid).collection('notification_slots').doc(slotKey);

  try {
    await slotRef.create({
      mode: 'daily',
      ruleId: rule.id,
      timezone,
      status: 'processing',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  } catch (error) {
    if (isAlreadyExists(error)) {
      return;
    }
    throw error;
  }

  try {
    const tasksSnapshot = await getTasksSnapshot();
    const summary = buildSummary(tasksSnapshot.docs, slotWindow.todayDate, slotWindow.tomorrowDate);

    if (summary.total === 0) {
      await slotRef.set(
        {
          status: 'skipped',
          reason: 'no_tasks',
          sentAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      return;
    }

    const devicesSnapshot = await getDevicesSnapshot();
    const tokens = extractTokens(devicesSnapshot.docs);
    if (tokens.length === 0) {
      await slotRef.set(
        {
          status: 'skipped',
          reason: 'no_devices',
          sentAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      return;
    }

    const notification = buildDailySummaryNotification(summary);
    const response = await admin.messaging().sendEachForMulticast({
      tokens,
      notification,
      data: {
        mode: 'daily',
        ruleId: rule.id,
        slotKey,
        timezone,
      },
    });

    await removeInvalidTokens(uid, devicesSnapshot.docs, tokens, response.responses);
    await slotRef.set(
      {
        status: 'sent',
        timezone,
        tokenCount: tokens.length,
        successCount: response.successCount,
        failureCount: response.failureCount,
        sentAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  } catch (error) {
    await slotRef.set(
      {
        status: 'error',
        error: String(error),
        sentAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    throw error;
  }
}

async function processDeadlineReminderRule({
  uid,
  timezone,
  slotWindow,
  rule,
  matchedTasks,
  getDevicesSnapshot,
}) {
  const slotKey = buildNotificationSlotKey({
    mode: 'deadline',
    ruleId: rule.id,
    slotStart: slotWindow.slotStart,
    timezone,
  });
  const slotRef = db.collection('users').doc(uid).collection('notification_slots').doc(slotKey);

  try {
    await slotRef.create({
      mode: 'deadline',
      ruleId: rule.id,
      timezone,
      status: 'processing',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  } catch (error) {
    if (isAlreadyExists(error)) {
      return;
    }
    throw error;
  }

  try {
    const devicesSnapshot = await getDevicesSnapshot();
    const tokens = extractTokens(devicesSnapshot.docs);
    if (tokens.length === 0) {
      await slotRef.set(
        {
          status: 'skipped',
          reason: 'no_devices',
          matchedCount: matchedTasks.length,
          sentAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      return;
    }

    const notification = buildDeadlineReminderNotification(matchedTasks, rule);
    const response = await admin.messaging().sendEachForMulticast({
      tokens,
      notification,
      data: {
        mode: 'deadline',
        ruleId: rule.id,
        slotKey,
        timezone,
      },
    });

    await removeInvalidTokens(uid, devicesSnapshot.docs, tokens, response.responses);
    await slotRef.set(
      {
        status: 'sent',
        timezone,
        matchedCount: matchedTasks.length,
        tokenCount: tokens.length,
        successCount: response.successCount,
        failureCount: response.failureCount,
        sentAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  } catch (error) {
    await slotRef.set(
      {
        status: 'error',
        error: String(error),
        sentAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    throw error;
  }
}

function extractTokens(deviceDocs) {
  return [
    ...new Set(
      deviceDocs
        .map((device) => device.data().token)
        .filter((token) => typeof token === 'string' && token.length > 0),
    ),
  ];
}

function isAlreadyExists(error) {
  return error && (error.code === 6 || error.code === 'already-exists');
}

async function removeInvalidTokens(uid, deviceDocs, tokens, responses) {
  const batch = db.batch();
  let hasDelete = false;

  for (let index = 0; index < responses.length; index += 1) {
    const response = responses[index];
    if (response.success) {
      continue;
    }
    const code = response.error?.code ?? '';
    if (code !== 'messaging/registration-token-not-registered') {
      continue;
    }

    const token = tokens[index] ?? null;
    const matchedDoc = deviceDocs.find((doc) => doc.data().token === token);
    if (!matchedDoc) {
      continue;
    }
    batch.delete(db.collection('users').doc(uid).collection('devices').doc(matchedDoc.id));
    hasDelete = true;
  }

  if (hasDelete) {
    await batch.commit();
  }
}
