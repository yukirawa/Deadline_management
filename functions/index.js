const { DateTime } = require('luxon');
const admin = require('firebase-admin');
const { logger } = require('firebase-functions');
const { onSchedule } = require('firebase-functions/v2/scheduler');

admin.initializeApp();

const db = admin.firestore();

const SLOT_WINDOWS = [{ hour: 7 }, { hour: 19 }];
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

  const profile = profileSnapshot.data();
  if (!profile.notificationsEnabled) {
    return;
  }

  const timezone = typeof profile.timezone === 'string' ? profile.timezone : 'Asia/Tokyo';
  const slot = resolveCurrentSlot(nowUtc, timezone);
  if (!slot) {
    return;
  }

  const slotRef = db.collection('users').doc(uid).collection('notification_slots').doc(slot.slotKey);
  try {
    await slotRef.create({
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
    const tasksSnapshot = await db
      .collection('users')
      .doc(uid)
      .collection('tasks')
      .where('isDeleted', '==', false)
      .where('done', '==', false)
      .get();

    const summary = buildSummary(tasksSnapshot.docs, slot.todayDate, slot.tomorrowDate);
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

    const devicesSnapshot = await db.collection('users').doc(uid).collection('devices').get();
    const tokens = [
      ...new Set(
        devicesSnapshot.docs
          .map((device) => device.data().token)
          .filter((token) => typeof token === 'string' && token.length > 0),
      ),
    ];

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

    const response = await admin.messaging().sendEachForMulticast({
      tokens,
      notification: {
        title: '締切レーダー',
        body: `未完了 ${summary.total}件（期限切れ${summary.overdue} / 今日${summary.today} / 明日${summary.tomorrow}）`,
      },
      data: {
        slotKey: slot.slotKey,
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

function resolveCurrentSlot(nowUtc, timezone) {
  const localNow = nowUtc.setZone(timezone);
  if (!localNow.isValid) {
    return null;
  }

  for (const slot of SLOT_WINDOWS) {
    if (localNow.hour === slot.hour && localNow.minute < 15) {
      const todayDate = localNow.toFormat('yyyy-MM-dd');
      const tomorrowDate = localNow.plus({ days: 1 }).toFormat('yyyy-MM-dd');
      const hh = String(slot.hour).padStart(2, '0');
      return {
        todayDate,
        tomorrowDate,
        slotKey: `${todayDate}_${hh}00_${timezone}`,
      };
    }
  }
  return null;
}

function buildSummary(taskDocs, todayDate, tomorrowDate) {
  let total = 0;
  let overdue = 0;
  let today = 0;
  let tomorrow = 0;

  for (const doc of taskDocs) {
    const dueDate = doc.data().dueDate;
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
