const http = require('http');
const { Server } = require('socket.io');
const { randomUUID } = require('crypto');

const {
	saveDrawingEvent,
	getWhiteboardState,
	broadcastEvent,
	subscribeToUpdates,
} = require('./store');

const PORT = Number(process.env.WS_PORT || process.env.PORT || 8080);
const HOST = process.env.WS_HOST || '0.0.0.0';
const SERVER_ID = randomUUID();

function buildEvent(type, payload) {
	return {
		type,
		payload: payload ?? null,
		timestamp: Date.now(),
		origin: SERVER_ID,
	};
}

async function start() {
	const server = http.createServer();
	const io = new Server(server, {
		cors: {
			origin: process.env.CORS_ORIGIN?.split(',') || '*',
			methods: ['GET', 'POST'],
		},
	});

	const unsubscribe = await subscribeToUpdates((event) => {
		if (!event || event.origin === SERVER_ID) {
			return;
		}

		switch (event.type) {
			case 'canvas:clear':
				io.emit('canvas:clear');
				break;
			case 'object:added':
			case 'object:modified':
			case 'object:removed':
				io.emit(event.type, event.payload);
				break;
			default:
				break;
		}
	});

	io.on('connection', async (socket) => {
		// eslint-disable-next-line no-console
		console.log(`client connected: ${socket.id}`);

		try {
			const objects = await getWhiteboardState();
			if (objects.length > 0) {
				socket.emit('object:sync', { objects });
			}
		} catch (err) {
			// eslint-disable-next-line no-console
			console.error('Failed to load whiteboard state', err);
		}

		const forward = (type) => async (payload) => {
			const event = buildEvent(type, payload);

			try {
				await saveDrawingEvent(event);
				await broadcastEvent(event);
				// Emit immediately to local clients (excluding sender) for low latency
				socket.broadcast.emit(type, payload);
				if (type === 'canvas:clear') {
					io.emit('canvas:clear');
				}
			} catch (err) {
				// eslint-disable-next-line no-console
				console.error(`Failed to handle event ${type}`, err);
			}
		};

		socket.on('object:added', forward('object:added'));
		socket.on('object:modified', forward('object:modified'));
		socket.on('object:removed', forward('object:removed'));
		socket.on('canvas:clear', forward('canvas:clear'));

		socket.on('disconnect', () => {
			// eslint-disable-next-line no-console
			console.log(`client disconnected: ${socket.id}`);
		});
	});

	systemSignals().forEach((signal) => {
		process.on(signal, async () => {
			// eslint-disable-next-line no-console
			console.log(`Received ${signal}, shutting down`);
			await unsubscribe();
			io.close();
			server.close(() => process.exit(0));
		});
	});

	server.listen(PORT, HOST, () => {
		// eslint-disable-next-line no-console
		console.log(`Whiteboard socket server listening on ${HOST}:${PORT}`);
	});
}

function systemSignals() {
	return ['SIGTERM', 'SIGINT'];
}

start().catch((err) => {
	// eslint-disable-next-line no-console
	console.error('Failed to start whiteboard socket server', err);
	process.exit(1);
});
