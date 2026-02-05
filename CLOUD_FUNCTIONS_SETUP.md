# 🚀 Telemetry Backend Deployment Guide

The code for the new architecture has been **successfully implemented** in your `firebase/functions` directory!

The architecture is set: **App -> Cloud Function (Ingest) -> Pub/Sub -> Cloud Function (Process) -> Firestore**.

## 🛑 Manual Actions Required (Do these first!)

### 1. Enable Blaze Plan (Billing)
Cloud Functions and Pub/Sub require the **Blaze (Pay-as-you-go)** plan.
- Go to the [Firebase Console](https://console.firebase.google.com/project/speed-data-tock/usage/details).
- Upgrade your project to the **Blaze** plan if you haven't already.

### 2. Enable Google Cloud APIs
You must enable the Pub/Sub API for your project.
- Go to the [Google Cloud Console - Pub/Sub API](https://console.cloud.google.com/marketplace/product/google/pubsub.googleapis.com?project=speed-data-tock).
- Click **Enable**.

---

## 🚀 Deploying the Backend

Once the above steps are done, you can deploy the new functions.

1. Open your terminal in the root folder (`d:\izaias\TOCK\Speed Data\speed-data`).
2. Run the deployment command:

```bash
firebase deploy --only functions
```

*Note: If you don't have the `firebase` command globally, try `npx firebase deploy --only functions` or install it with `npm install -g firebase-tools`.*

### Verify Deployment
After deployment, go to the **Functions** tab in the Firebase Console. You should see two functions:
- `ingestTelemetry` (HTTPS Trigger)
- `processTelemetry` (Pub/Sub Trigger)

And in the **Pub/Sub** section of Google Cloud Console, you should see a topic named `telemetry-topic`.

---

## ✅ App Status
- The Flutter App is already updated to buffer data and send it to `ingestTelemetry` every 10 seconds.
- It no longer writes directly to Firestore for location updates.
- It uses 100ms sampling (volatile memory) for high precision.

You are good to go! 🏁
