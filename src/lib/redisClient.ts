import 'server-only';

import { createClient, type RedisClientType } from 'redis';

const DEFAULT_HOST = process.env.REDIS_HOST ?? 'redis';
const DEFAULT_URL = `redis://${DEFAULT_HOST}:6379`;
const REDIS_URL = process.env.REDIS_URL ?? DEFAULT_URL;

let client: RedisClientType | null = null;
let clientPromise: Promise<RedisClientType> | null = null;

const handleError = (err: unknown) => {
	// eslint-disable-next-line no-console
	console.error('Redis Client Error', err);
};

const connectClient = () => {
	if (!client) {
		client = createClient({ url: REDIS_URL });
		client.on('error', handleError);
	}

	if (!clientPromise) {
		clientPromise = client
			.connect()
			.then(() => client as RedisClientType)
			.catch((err) => {
				clientPromise = null;
				client = null;
				throw err;
			});
	}

	return clientPromise;
};

export const getRedisClient = async () => {
	if (client && client.isOpen) {
		return client;
	}

	return connectClient();
};

export const getRedisSubscriber = async () => {
	const base = await getRedisClient();
	const subscriber = base.duplicate();
	subscriber.on('error', handleError);
	await subscriber.connect();
	return subscriber;
};
