const TARGET = "test";

class ReconnectableWebSocket {
    url: string;
    retryInterval: number;
    reconnectLoopId: number;
    socket: WebSocket | undefined;

    constructor() {
        this.url = "ws://127.0.0.1:7542";
        this.retryInterval = 5000;
        this.reconnectLoopId = -1;
    }

    connect() {
        console.log(`Attempting to connect to ${this.url}`);
        this.socket = new WebSocket(this.url);

        this.socket.onopen = () => {
            console.log("WebSocket connection established.");

            this.socket?.send(JSON.stringify({
                target: TARGET,
                type: "target"
            }));

            this.sendAppData();
            
            if (this.reconnectLoopId !== -1) {
                clearInterval(this.reconnectLoopId);
                this.reconnectLoopId = -1;
            }
        };
        
        this.socket.onmessage = msg => {
            this.handleCommand(msg.data.toLowerCase());
        };

        this.socket.onclose = () => {
            console.warn("WebSocket closed. Reconnecting...");
            
            if (this.reconnectLoopId === -1) {
                this.reconnectLoopId = setInterval(() => this.connect(), this.retryInterval);
            }
        };

        this.socket.onerror = () => {
            console.error("WebSocket error. Reconnecting...");
            this.socket?.close();
        };
    }

    async handleCommand(command: string) {
        console.log("Got command: " + command);

        await this.sendAppData();
    }

    async sendAppData() {
        if (!this.socket || this.socket?.readyState !== WebSocket.OPEN) {
            console.log("Socket not opened");
            return;
        }

        this.socket?.send(JSON.stringify({
            target: TARGET,
            type: "sync",
            data: {
                foo: "bar"
            }
        }));
    }
}

new ReconnectableWebSocket().connect();
