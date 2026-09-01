import asyncio

LISTEN_HOST = "0.0.0.0"
LISTEN_PORT = 18080

BACKEND_HOST = "llm-backend"
BACKEND_PORT = 8080

DELAY_SECONDS = 8


async def handle_client(reader, writer):
    backend_reader = None
    backend_writer = None

    try:
        request_headers = await reader.readuntil(b"\r\n\r\n")

        header_text = request_headers.decode(
            "latin-1",
            errors="replace",
        )

        content_length = 0

        for line in header_text.split("\r\n"):
            if line.lower().startswith("content-length:"):
                content_length = int(
                    line.split(":", 1)[1].strip()
                )

        body = b""

        if content_length > 0:
            body = await reader.readexactly(content_length)

        print(
            "FAULT PROXY: request received",
            flush=True,
        )

        backend_reader, backend_writer = await asyncio.open_connection(
            BACKEND_HOST,
            BACKEND_PORT,
        )

        backend_writer.write(request_headers)
        backend_writer.write(body)
        await backend_writer.drain()

        print(
            f"FAULT PROXY: backend request sent, "
            f"sleeping {DELAY_SECONDS}s",
            flush=True,
        )

        await asyncio.sleep(DELAY_SECONDS)

        print(
            "FAULT PROXY: forwarding backend response",
            flush=True,
        )

        response_headers = await backend_reader.readuntil(
            b"\r\n\r\n"
        )

        writer.write(response_headers)
        await writer.drain()

        while True:
            chunk = await backend_reader.read(4096)

            if not chunk:
                break

            writer.write(chunk)
            await writer.drain()

    except Exception as exc:

        print(
            f"FAULT PROXY ERROR: "
            f"{type(exc).__name__}: {exc}",
            flush=True,
        )

    finally:

        if backend_writer is not None:
            backend_writer.close()

            try:
                await backend_writer.wait_closed()
            except Exception:
                pass

        writer.close()

        try:
            await writer.wait_closed()
        except Exception:
            pass


async def main():

    server = await asyncio.start_server(
        handle_client,
        LISTEN_HOST,
        LISTEN_PORT,
    )

    print(
        f"Fault proxy listening on "
        f"{LISTEN_HOST}:{LISTEN_PORT}",
        flush=True,
    )

    async with server:
        await server.serve_forever()


if __name__ == "__main__":
    asyncio.run(main())
