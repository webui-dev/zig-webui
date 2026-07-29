(() => {
    const signature = 0xdd;
    const commandJs = 0xfe;
    const commandJsQuick = 0xfd;
    const commandClick = 0xfc;
    const commandNavigation = 0xfb;
    const commandClose = 0xfa;
    const commandCall = 0xf9;
    const commandRaw = 0xf8;
    const commandCheckToken = 0xf5;
    const encoder = new TextEncoder();
    const decoder = new TextDecoder();
    const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
    const pending = new Map();
    const event = Object.freeze({
        CONNECTED: 0,
        DISCONNECTED: 1,
    });
    let nextId = 1;
    let connected = false;
    let logging = false;
    let allowNavigation = !globalThis.__zigWebuiEvents;
    let eventCallback = null;
    let lastEvent = -1;

    const bridgeSource = document.currentScript?.src
        ? new URL(document.currentScript.src)
        : new URL(location.href, `${location.protocol}//${location.host}`);
    const socket = new WebSocket(
        `${bridgeSource.protocol === "https:" ? "wss" : "ws"}://${bridgeSource.host}/${globalThis.__zigWebuiCapability}/_webui_ws_connect`,
    );
    socket.binaryType = "arraybuffer";

    function packet(command, id, payload = new Uint8Array()) {
        const bytes = new Uint8Array(8 + payload.length);
        const view = new DataView(bytes.buffer);
        bytes[0] = signature;
        view.setUint32(1, globalThis.__zigWebuiToken, true);
        view.setUint16(5, id, true);
        bytes[7] = command;
        bytes.set(payload, 8);
        return bytes;
    }

    function sendEvent(command, value) {
        if (connected)
            socket.send(packet(command, 0, encoder.encode(value)));
    }

    function log(message) {
        if (logging) console.log(`WebUI -> ${message}`);
    }

    function emitEvent(value) {
        if (eventCallback && value !== lastEvent) {
            lastEvent = value;
            eventCallback(value);
        }
    }

    // ponytail: Zig filters IDs to avoid injecting names; send a filtered
    // list only if pages with many unrelated IDs make click traffic matter.
    if (globalThis.__zigWebuiEvents || globalThis.__zigWebuiDomBindings) {
        document.addEventListener("click", (event) => {
            const element = event.target?.closest?.("[id]");
            if (element) sendEvent(commandClick, element.id);

            if (globalThis.__zigWebuiEvents &&
                !allowNavigation &&
                !("navigation" in globalThis))
            {
                const link = event.target?.closest?.("a[href]");
                if (link && connected) {
                    event.preventDefault();
                    sendEvent(commandNavigation, link.href);
                }
            }
        });
    }
    if (globalThis.__zigWebuiEvents && "navigation" in globalThis) {
        globalThis.navigation.addEventListener("navigate", (event) => {
            if (!connected || allowNavigation) return;
            if (event.cancelable) event.preventDefault();
            sendEvent(commandNavigation, event.destination.url);
        });
    }

    socket.onopen = () => {
        log("Connected");
        socket.send(
            packet(commandCheckToken, 0, encoder.encode(globalThis.__zigWebuiCapability)),
        );
    };
    socket.onclose = () => {
        connected = false;
        log("Disconnected");
        for (const promise of pending.values())
            promise.reject(new Error("WebUI connection closed"));
        pending.clear();
        emitEvent(event.DISCONNECTED);
    };
    socket.onmessage = async ({ data }) => {
        const bytes = new Uint8Array(data);
        if (bytes.length < 8 || bytes[0] !== signature) return;
        const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
        const id = view.getUint16(5, true);
        if (bytes[7] === commandCheckToken) {
            connected = bytes.length > 8 && bytes[8] === 1;
            if (connected) emitEvent(event.CONNECTED);
            return;
        }
        if (bytes[7] === commandJs || bytes[7] === commandJsQuick) {
            let failed = 0;
            let value;
            try {
                const source = decoder.decode(bytes.subarray(8)).replace(/\0$/, "");
                const result = await AsyncFunction(source)();
                value = result instanceof Uint8Array
                    ? result
                    : encoder.encode(String(result));
            } catch (error) {
                failed = 1;
                value = encoder.encode(
                    error instanceof Error ? error.message : String(error),
                );
            }
            if (bytes[7] === commandJsQuick) return;
            const response = new Uint8Array(value.length + 2);
            response[0] = failed;
            response.set(value, 1);
            socket.send(packet(commandJs, id, response));
            return;
        }
        if (bytes[7] === commandNavigation) {
            location.href = decoder.decode(bytes.subarray(8));
            return;
        }
        if (bytes[7] === commandClose) {
            socket.close();
            globalThis.close();
            return;
        }
        if (bytes[7] === commandRaw) {
            const separator = bytes.indexOf(0, 8);
            if (separator < 0) return;
            const functionName = decoder.decode(bytes.subarray(8, separator));
            const callback = globalThis[functionName];
            if (typeof callback === "function")
                callback(bytes.subarray(separator + 1));
            return;
        }
        if (bytes[7] === commandCall) {
            const promise = pending.get(id);
            if (promise) {
                pending.delete(id);
                promise.resolve(decoder.decode(bytes.subarray(8)));
            }
        }
    };

    globalThis.webui = {
        event,
        isConnected: () => connected,
        call(name, ...args) {
            if (!connected) return Promise.reject(new Error("WebUI is not connected"));
            log(`Calling [${name}(...)]`);
            const values = args.map((arg) =>
                arg instanceof Uint8Array ? arg : encoder.encode(String(arg)),
            );
            const lengths = encoder.encode(values.map((value) => value.length).join(";"));
            const nameBytes = encoder.encode(name);
            const size =
                nameBytes.length + 1 +
                lengths.length + 1 +
                values.reduce((total, value) => total + value.length + 1, 0);
            const payload = new Uint8Array(size);
            let at = 0;
            payload.set(nameBytes, at);
            at += nameBytes.length + 1;
            payload.set(lengths, at);
            at += lengths.length + 1;
            for (const value of values) {
                payload.set(value, at);
                at += value.length + 1;
            }

            const id = nextId++ & 0xffff || nextId++ & 0xffff;
            return new Promise((resolve, reject) => {
                pending.set(id, { resolve, reject });
                try {
                    socket.send(packet(commandCall, id, payload));
                } catch (error) {
                    pending.delete(id);
                    reject(error);
                }
            });
        },
        setLogging(status) {
            logging = Boolean(status);
            console.log(`WebUI -> Log ${logging ? "Enabled" : "Disabled"}.`);
        },
        encode(data) {
            return globalThis.btoa(data);
        },
        decode(data) {
            return globalThis.atob(data);
        },
        setEventCallback(callback) {
            if (typeof callback !== "function")
                throw new TypeError("Event callback must be a function");
            eventCallback = callback;
        },
        async isHighContrast() {
            if (globalThis.matchMedia?.("(forced-colors: active)").matches)
                return true;
            return globalThis.matchMedia?.("(prefers-contrast: more)").matches ?? false;
        },
        allowNavigation(status) {
            allowNavigation = Boolean(status);
        },
    };
})();
