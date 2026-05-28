const WebSocket = require('ws');
const crypto = require('crypto');

const PORT = process.env.PORT || 8915;
const wss = new WebSocket.Server({ port: PORT });

// roomCode -> { hostWs, clients: [ws1, ws2...] }
const rooms = new Map();

wss.on('connection', (ws) => {
    let currentRoom = null;
    let isHost = false;
    // Assign a simple ID to the client (1 is reserved for Godot's Host)
    ws.id = Math.floor(Math.random() * 1000000) + 2;

    ws.on('message', (message) => {
        try {
            const data = JSON.parse(message);
            
            if (data.type === 'host') {
                isHost = true;
                ws.id = 1; // Godot server peer ID is always 1
                currentRoom = crypto.randomBytes(2).toString('hex').toUpperCase();
                rooms.set(currentRoom, { hostWs: ws, clients: [] });
                console.log(`Room created: ${currentRoom}`);
                ws.send(JSON.stringify({ type: 'room_created', room: currentRoom }));
                return;
            }

            if (data.type === 'join') {
                const roomCode = data.room.toUpperCase();
                if (!rooms.has(roomCode)) {
                    ws.send(JSON.stringify({ type: 'error', message: 'Room not found.' }));
                    return;
                }
                currentRoom = roomCode;
                const room = rooms.get(currentRoom);
                room.clients.push(ws);
                console.log(`Client ${ws.id} joined room: ${currentRoom}`);
                
                // Tell the client who else is in the room (the host ID)
                ws.send(JSON.stringify({ type: 'joined', id: ws.id, peers: [1] }));
                // Tell the host about the new peer
                room.hostWs.send(JSON.stringify({ type: 'peer_connected', id: ws.id }));
                return;
            }

            // Route SDP / ICE candidates
            if (['offer', 'answer', 'candidate'].includes(data.type)) {
                if (!currentRoom || !rooms.has(currentRoom)) return;
                const room = rooms.get(currentRoom);
                const targetId = data.to;
                
                let targetWs = null;
                if (targetId === 1) targetWs = room.hostWs;
                else targetWs = room.clients.find(c => c.id === targetId);
                
                if (targetWs) {
                    data.from = ws.id;
                    targetWs.send(JSON.stringify(data));
                }
            }

        } catch (e) {
            console.error('Invalid message:', message, e);
        }
    });

    ws.on('close', () => {
        if (!currentRoom) return;
        const room = rooms.get(currentRoom);
        if (!room) return;
        
        if (isHost) {
            console.log(`Host left room: ${currentRoom}`);
            room.clients.forEach(c => c.send(JSON.stringify({ type: 'error', message: 'Host disconnected.' })));
            rooms.delete(currentRoom);
        } else {
            console.log(`Client ${ws.id} left room: ${currentRoom}`);
            room.clients = room.clients.filter(c => c !== ws);
            if (room.hostWs.readyState === WebSocket.OPEN) {
                room.hostWs.send(JSON.stringify({ type: 'peer_disconnected', id: ws.id }));
            }
        }
    });
});

console.log(`Signaling server running on port ${PORT}`);
