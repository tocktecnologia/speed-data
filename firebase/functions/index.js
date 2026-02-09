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

    const { raceId, uid, points, checkpoints } = data;

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

    // --- ALGORITHM START ---
    try {
        if (checkpoints && checkpoints.length > 0) {
            const db = admin.firestore();

            // Helper: distance in meters
            function getDistance(lat1, lon1, lat2, lon2) {
                const R = 6371e3; // metres
                const φ1 = lat1 * Math.PI / 180;
                const φ2 = lat2 * Math.PI / 180;
                const Δφ = (lat2 - lat1) * Math.PI / 180;
                const Δλ = (lon2 - lon1) * Math.PI / 180;
                const a = Math.sin(Δφ / 2) * Math.sin(Δφ / 2) +
                    Math.cos(φ1) * Math.cos(φ2) *
                    Math.sin(Δλ / 2) * Math.sin(Δλ / 2);
                const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
                return R * c;
            }

            // Iterate over Checkpoints (PM)
            for (let i = 0; i < checkpoints.length; i++) {
                const pm = checkpoints[i];
                const nextPm = checkpoints[(i + 1) % checkpoints.length];

                // Find closest PP that meets conditions
                let bestPP = null;
                let minDist = 41.6; // Max allowed distance (15m)

                for (const pp of points) {
                    const dist = getDistance(pm.lat, pm.lng, pp.lat, pp.lng);

                    if (dist < minDist) {
                        // Check "Posterior" / Direction
                        // Vector Track: PM -> NextPM
                        const vTrackLat = nextPm.lat - pm.lat;
                        const vTrackLng = nextPm.lng - pm.lng;

                        // Vector Pilot: PM -> PP
                        const vPilotLat = pp.lat - pm.lat;
                        const vPilotLng = pp.lng - pm.lng;

                        // Dot Product: if > 0, pilot is "ahead" or aligned with track direction from PM
                        const dot = (vPilotLat * vTrackLat) + (vPilotLng * vTrackLng);

                        if (dot > 0) {
                            minDist = dist;
                            bestPP = pp;
                        }
                    }
                }

                if (bestPP) {
                    // Interaction with Firestore Laps
                    const lapsRef = db.collection('races').doc(raceId).collection('participants').doc(uid).collection('laps');

                    // Get 'latest' lap
                    const lapsSnapshot = await lapsRef.orderBy('number', 'desc').limit(1).get();

                    let currentLapDoc = null;
                    let currentLapData = null;

                    if (lapsSnapshot.empty) {
                        // Create Lap 1
                        const newLapRef = lapsRef.doc('lap_1');
                        const newLapData = {
                            number: 1,
                            created_at: admin.firestore.FieldValue.serverTimestamp(),
                            points: {}
                        };
                        await newLapRef.set(newLapData);
                        currentLapDoc = newLapRef;
                        currentLapData = newLapData;
                    } else {
                        currentLapDoc = lapsSnapshot.docs[0].ref;
                        currentLapData = lapsSnapshot.docs[0].data();
                    }

                    // Check if point for THIS checkpoint is already added
                    const cpKey = `cp_${i}`;
                    const existingPoint = currentLapData.points && currentLapData.points[cpKey];

                    if (!existingPoint) {
                        // Add point
                        const updateData = {};
                        updateData[`points.${cpKey}`] = bestPP;
                        // We use dot notation to update specific map field without overwriting entire map
                        await currentLapDoc.update(updateData);
                        // Update local data for subsequent loop checks if needed (though we fetch fresh usually, but here we are in loop)
                        if (!currentLapData.points) currentLapData.points = {};
                        currentLapData.points[cpKey] = bestPP;

                    } else {
                        // Already exists, check timestamp
                        const existingTime = existingPoint.timestamp;
                        const newTime = bestPP.timestamp;
                        const diffSeconds = (newTime - existingTime) / 1000;

                        if (diffSeconds >= 20) {
                            // Check if ALL checkpoints are present in current lap
                            const totalCheckpoints = checkpoints.length;
                            const recordedCheckpoints = currentLapData.points ? Object.keys(currentLapData.points).length : 0;

                            if (recordedCheckpoints >= (totalCheckpoints - 1)) {
                                // Create Next Lap
                                const nextLapNum = currentLapData.number + 1;
                                const nextLapRef = lapsRef.doc(`lap_${nextLapNum}`);
                                await nextLapRef.set({
                                    number: nextLapNum,
                                    created_at: admin.firestore.FieldValue.serverTimestamp(),
                                    points: {
                                        [cpKey]: bestPP // Add the point to the NEW lap
                                    }
                                });
                            }
                        }
                        // If < 30s, do nothing.
                    }
                }
            }
        }
    } catch (e) {
        console.error('Error in algorithm:', e);
        // Continue to PubSub even if algorithm fails? User said "Independente... envie para bigquery"
    }
    // --- ALGORITHM END ---

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
