const { createClient } = require('redis');

const DEFAULT_HOST = process.env.REDIS_HOST || 'redis';
const DEFAULT_URL = `redis://${DEFAULT_HOST}:6379`;
const REDIS_URL = process.env.REDIS_URL || DEFAULT_URL;

let client;
let connectPromise;

const logError = (err) => {
	// eslint-disable-next-line no-console
	console.error('Redis Client Error', err);
};

async function getRedisClient() {
	if (client && client.isOpen) {
		return client;
	}

	if (!connectPromise) {
		client = createClient({ url: REDIS_URL });
		client.on('error', logError);
		connectPromise = client
			.connect()
			.then(() => client)
			.catch((err) => {
				connectPromise = null;
				throw err;
			});
	}

	await connectPromise;
	return client;
}

async function createSubscriber() {
	const baseClient = await getRedisClient();
	const subscriber = baseClient.duplicate();
	subscriber.on('error', logError);
	await subscriber.connect();
	return subscriber;
}

module.exports = {
	getRedisClient,
	createSubscriber,
	REDIS_URL,
};
