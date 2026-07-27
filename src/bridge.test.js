const assert = require("node:assert/strict");
const test = require("node:test");

test("bridge handles targeted navigation, raw data, and close", async () => {
    class WebSocketMock {
        static instance;

        constructor(url) {
            this.url = url;
            this.closed = false;
            WebSocketMock.instance = this;
        }

        close() {
            this.closed = true;
        }

        send() {}
    }

    const encoder = new TextEncoder();
    const frame = (command, payload = new Uint8Array()) => {
        const bytes = new Uint8Array(8 + payload.length);
        bytes[0] = 0xdd;
        bytes[7] = command;
        bytes.set(payload, 8);
        return bytes;
    };

    let windowClosed = false;
    let received;
    globalThis.WebSocket = WebSocketMock;
    globalThis.location = {
        protocol: "http:",
        host: "localhost",
        href: "/",
    };
    globalThis.close = () => {
        windowClosed = true;
    };
    globalThis.receiveRaw = (data) => {
        received = [...data];
    };

    try {
        require("./bridge.js");
        const socket = WebSocketMock.instance;
        assert.equal(socket.url, "ws://localhost/_webui_ws_connect");

        await socket.onmessage({
            data: frame(0xfb, encoder.encode("/next")),
        });
        assert.equal(globalThis.location.href, "/next");

        const name = encoder.encode("receiveRaw");
        const raw = new Uint8Array(name.length + 4);
        raw.set(name);
        raw.set([0, 0, 1, 255], name.length);
        await socket.onmessage({ data: frame(0xf8, raw) });
        assert.deepEqual(received, [0, 1, 255]);

        await socket.onmessage({ data: frame(0xfa) });
        assert.equal(socket.closed, true);
        assert.equal(windowClosed, true);
    } finally {
        delete globalThis.WebSocket;
        delete globalThis.location;
        delete globalThis.close;
        delete globalThis.receiveRaw;
        delete globalThis.webui;
    }
});
