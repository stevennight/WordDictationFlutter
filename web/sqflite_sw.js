// sqflite service worker for web support
// This file is required for sqflite_common_ffi_web to work properly

importScripts('https://unpkg.com/sql.js@1.8.0/dist/sql-wasm.js');

const CACHE_NAME = 'sqflite-cache-v1';

self.addEventListener('install', (event) => {
  console.log('Service Worker installing.');
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  console.log('Service Worker activating.');
  event.waitUntil(self.clients.claim());
});

self.addEventListener('message', (event) => {
  console.log('Service Worker received message:', event.data);
  // Handle sqflite operations here
});

// Initialize SQL.js
self.addEventListener('fetch', (event) => {
  // Handle fetch events if needed
});