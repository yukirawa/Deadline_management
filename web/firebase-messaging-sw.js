/* eslint-disable no-undef */
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-app-compat.js');
importScripts(
  'https://www.gstatic.com/firebasejs/10.14.1/firebase-messaging-compat.js',
);

firebase.initializeApp({
  apiKey: 'AIzaSyAE2NUUVa9HxW9xAS_yL0pKxjP4DjneSFk',
  appId: '1:836327247315:web:eb0250d1e85c0b8fac7326',
  messagingSenderId: '836327247315',
  projectId: 'cram-companion-9o3zs',
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
