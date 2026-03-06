/* eslint-disable no-undef */
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-app-compat.js');
importScripts(
  'https://www.gstatic.com/firebasejs/10.14.1/firebase-messaging-compat.js',
);

firebase.initializeApp({
  apiKey: 'YOUR_FIREBASE_WEB_API_KEY',
  appId: 'YOUR_FIREBASE_WEB_APP_ID',
  messagingSenderId: 'YOUR_FIREBASE_MESSAGING_SENDER_ID',
  projectId: 'YOUR_FIREBASE_PROJECT_ID',
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  const notificationTitle = payload.notification?.title ?? '締切レーダー';
  const notificationOptions = {
    body: payload.notification?.body ?? '',
    icon: '/deadline/icons/Icon-192.png',
  };

  self.registration.showNotification(notificationTitle, notificationOptions);
});
