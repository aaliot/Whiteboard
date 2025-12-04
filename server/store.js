const { getRedisClient, createSubscriber } = require('./redisClient');

const EVENTS_KEY = process.env.WHITEBOARD_EVENTS_KEY || 'whiteboard_events';
const UPDATES_CHANNEL = process.env.WHITEBOARD_UPDATES_CHANNEL || 'whiteboard_updates';
const MAX_EVENTS = Number(process.env.WHITEBOARD_MAX_EVENTS || 500);

function parseEvent(raw) {
	try {
		return JSON.parse(raw);
	} catch (err) {
		// eslint-disable-next-line no-console
		console.error('Failed to parse whiteboard event', err);
		return null;
	}
}

function rebuildState(events) {
	const objects = new Map();

	events.forEach((event) => {
		if (!event || !event.type) {
			return;
		}

		switch (event.type) {
			case 'canvas:clear': {
				objects.clear();
				break;
			}
			case 'object:removed': {
				const id = event.payload?.id;
				if (id) {
					objects.delete(id);
				}
				break;
			}
			case 'object:modified':
			case 'object:added': {
				const payload = event.payload;
				const id = payload?.id;
				if (!id) {
					return;
				}
				const prev = objects.get(id) || {};
				objects.set(id, { ...prev, ...payload });
				break;
			}
			default:
				break;
		}
	});

	return Array.from(objects.values());
}

async function saveDrawingEvent(event) {
	const client = await getRedisClient();

	if (event.type === 'canvas:clear') {
		await client.del(EVENTS_KEY);
		return;
	}

	await client.rPush(EVENTS_KEY, JSON.stringify(event));

	if (MAX_EVENTS > 0) {
		await client.lTrim(EVENTS_KEY, -MAX_EVENTS, -1);
	}
}

async function getWhiteboardState() {
	const client = await getRedisClient();
	const raw = await client.lRange(EVENTS_KEY, 0, -1);
	const events = raw.map(parseEvent).filter(Boolean);
	return rebuildState(events);
}

async function broadcastEvent(event) {
	const client = await getRedisClient();
	await client.publish(UPDATES_CHANNEL, JSON.stringify(event));
}

async function subscribeToUpdates(handler) {
	const subscriber = await createSubscriber();
	await subscriber.subscribe(UPDATES_CHANNEL, (message) => {
		const event = parseEvent(message);
		if (event) {
			handler(event);
		}
	});

	return async () => {
		await subscriber.unsubscribe(UPDATES_CHANNEL);
		await subscriber.quit();
	};
}

module.exports = {
	saveDrawingEvent,
	getWhiteboardState,
	broadcastEvent,
	subscribeToUpdates,
	UPDATES_CHANNEL,
	EVENTS_KEY,
	MAX_EVENTS,
};
