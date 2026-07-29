const assert = require("node:assert/strict");
const test = require("node:test");

test("bridge handles commands and external script origins", async () => {
    class WebSocketMock {
        static instance;

        constructor(url) {
            this.url = url;
            this.closed = false;
            this.sent = undefined;
            this.sendCount = 0;
            WebSocketMock.instance = this;
        }

        close() {
            this.closed = true;
        }

        send(data) {
            this.sent = data;
            this.sendCount += 1;
        }
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
    let clickListener;
    globalThis.WebSocket = WebSocketMock;
    globalThis.__zigWebuiCapability = "0123456789abcdef0123456789abcdef";
    globalThis.__zigWebuiEvents = true;
    globalThis.__zigWebuiDomBindings = false;
    globalThis.__zigWebuiToken = 7;
    globalThis.document = {
        addEventListener(type, listener) {
            if (type === "click") clickListener = listener;
        },
    };
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
        assert.equal(
            socket.url,
            "ws://localhost/0123456789abcdef0123456789abcdef/_webui_ws_connect",
        );
        socket.onopen();
        assert.equal(
            new TextDecoder().decode(new Uint8Array(socket.sent).subarray(8)),
            globalThis.__zigWebuiCapability,
        );
        await socket.onmessage({
            data: frame(0xf5, Uint8Array.of(1)),
        });
        const sendsBeforeQuick = socket.sendCount;
        await socket.onmessage({
            data: frame(
                0xfd,
                encoder.encode("globalThis.quickResult = 42"),
            ),
        });
        assert.equal(globalThis.quickResult, 42);
        assert.equal(socket.sendCount, sendsBeforeQuick);

        const button = { id: "run" };
        clickListener({
            target: {
                closest(selector) {
                    return selector === "[id]" ? button : null;
                },
            },
        });
        let eventPacket = new Uint8Array(socket.sent);
        assert.equal(eventPacket[7], 0xfc);
        assert.equal(
            new TextDecoder().decode(eventPacket.subarray(8)),
            "run",
        );

        let prevented = false;
        const link = { href: "http://localhost/next" };
        clickListener({
            target: {
                closest(selector) {
                    return selector === "a[href]" ? link : null;
                },
            },
            preventDefault() {
                prevented = true;
            },
        });
        eventPacket = new Uint8Array(socket.sent);
        assert.equal(prevented, true);
        assert.equal(eventPacket[7], 0xfb);
        assert.equal(
            new TextDecoder().decode(eventPacket.subarray(8)),
            link.href,
        );

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

        let navigationListener;
        globalThis.navigation = {
            addEventListener(type, listener) {
                if (type === "navigate") navigationListener = listener;
            },
        };
        globalThis.document.currentScript = {
            src: "https://bridge.example:9443/capability/webui.js",
        };
        delete globalThis.webui;
        delete require.cache[require.resolve("./bridge.js")];
        require("./bridge.js");
        const navigationSocket = WebSocketMock.instance;
        assert.equal(
            navigationSocket.url,
            "wss://bridge.example:9443/0123456789abcdef0123456789abcdef/_webui_ws_connect",
        );
        navigationSocket.onopen();
        await navigationSocket.onmessage({
            data: frame(0xf5, Uint8Array.of(1)),
        });
        prevented = false;
        navigationListener({
            cancelable: true,
            destination: { url: "http://localhost/history" },
            preventDefault() {
                prevented = true;
            },
        });
        eventPacket = new Uint8Array(navigationSocket.sent);
        assert.equal(prevented, true);
        assert.equal(eventPacket[7], 0xfb);
        assert.equal(
            new TextDecoder().decode(eventPacket.subarray(8)),
            "http://localhost/history",
        );

        delete globalThis.navigation;
        globalThis.__zigWebuiEvents = false;
        globalThis.__zigWebuiDomBindings = true;
        clickListener = undefined;
        delete globalThis.webui;
        delete require.cache[require.resolve("./bridge.js")];
        require("./bridge.js");
        const bindingSocket = WebSocketMock.instance;
        bindingSocket.onopen();
        await bindingSocket.onmessage({
            data: frame(0xf5, Uint8Array.of(1)),
        });
        assert.equal(typeof clickListener, "function");

        const dynamicButton = { id: "dynamic-binding" };
        clickListener({
            target: {
                closest(selector) {
                    return selector === "[id]" ? dynamicButton : null;
                },
            },
        });
        eventPacket = new Uint8Array(bindingSocket.sent);
        assert.equal(eventPacket[7], 0xfc);
        assert.equal(
            new TextDecoder().decode(eventPacket.subarray(8)),
            dynamicButton.id,
        );

        prevented = false;
        const sendsBeforeLink = bindingSocket.sendCount;
        clickListener({
            target: {
                closest() {
                    return null;
                },
            },
            preventDefault() {
                prevented = true;
            },
        });
        assert.equal(prevented, false);
        assert.equal(bindingSocket.sendCount, sendsBeforeLink);
    } finally {
        delete globalThis.WebSocket;
        delete globalThis.document;
        delete globalThis.location;
        delete globalThis.navigation;
        delete globalThis.close;
        delete globalThis.receiveRaw;
        delete globalThis.quickResult;
        delete globalThis.webui;
        delete globalThis.__zigWebuiCapability;
        delete globalThis.__zigWebuiDomBindings;
        delete globalThis.__zigWebuiEvents;
        delete globalThis.__zigWebuiToken;
    }
});
