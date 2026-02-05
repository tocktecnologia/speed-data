const functions = require('firebase-functions');
const admin = require('firebase-admin');
const { PubSub } = require('@google-cloud/pubsub');
const { BigQuery } = require('@google-cloud/bigquery');

admin.initializeApp();

// Instantiate Pub/Sub client
const pubsub = new PubSub();
const TOPIC_NAME = 'telemetry-topic';

/**
 * Cloud Function: ingestTelemetry
 * Receives a batch of telemetry points and publishes them to Pub/Sub.
 * This ensures fast response to the client and asynchronous processing.
 */
exports.ingestTelemetry = functions.https.onCall(async (data, context) => {
    // 1. Authentication Check
    if (!context.auth) {
        throw new functions.https.HttpsError(
            'unauthenticated',
            'User must be logged in to send telemetry.'
        );
    }

    const { raceId, uid, points } = data;

    // 2. Validation
    if (!points || !Array.isArray(points)) {
        throw new functions.https.HttpsError(
            'invalid-argument',
            'Points must be an array.'
        );
    }

    if (points.length === 0) {
        return { success: true, count: 0 };
    }

    console.log(`Received ${points.length} points for race ${raceId} from user ${uid}`);

    // 3. Publish to Pub/Sub
    // We publish the entire batch as a single message to optimize throughput.
    const messagePayload = {
        raceId,
        uid,
        points,
        ingestedAt: Date.now(),
        userEmail: context.auth.token.email || null
    };

    const dataBuffer = Buffer.from(JSON.stringify(messagePayload));

    try {
        const topic = pubsub.topic(TOPIC_NAME);
        const messageId = await topic.publishMessage({ data: dataBuffer });
        console.log(`Message ${messageId} published.`);

        return { success: true, messageId };
    } catch (error) {
        console.error('Processing Error:', error);
        throw new functions.https.HttpsError(
            'internal',
            'Failed to process telemetry.'
        );
    }
});

/**
 * (Optional) Pub/Sub Trigger to Process Data
 * This function triggers when a message is published to 'telemetry-topic'.
 * It handles the "Heavy Lifting": Writing to BigQuery, updating Aggregates, etc.
 * AND updates the "Current State" in Firestore as per the architecture.
 */
exports.processTelemetry = functions.pubsub.topic(TOPIC_NAME).onPublish(async (message) => {
    const payload = message.json; // Automatic JSON parsing
    const { raceId, uid, points, ingestedAt } = payload;

    console.log(`Processing batch for race: ${raceId}, user: ${uid}`);

    const tasks = [];

    // TASK 1: Update Real-Time State (Firestore)
    // "Cloud Function -> Firestore (estado / tempo real)"
    if (points && points.length > 0) {
        const lastPoint = points[points.length - 1]; // Assuming time-ordered
        const updateTask = admin.firestore()
            .collection('races')
            .doc(raceId)
            .collection('participants')
            .doc(uid)
            .set({
                current: {
                    lat: lastPoint.lat,
                    lng: lastPoint.lng,
                    speed: lastPoint.speed,
                    heading: lastPoint.heading,
                    altitude: lastPoint.altitude || 0,
                    timestamp: lastPoint.timestamp,
                    last_updated: admin.firestore.FieldValue.serverTimestamp()
                }
            }, { merge: true });

        tasks.push(updateTask);
    }

    // TASK 2: Insert into BigQuery (Example)
    const bigquery = new BigQuery();
    tasks.push(bigquery.dataset('telemetry').table('raw_points').insert(points.map(p => ({ ...p, raceId, uid }))));

    await Promise.all(tasks);
});
