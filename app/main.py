import logging
import os
import time
import uuid
from collections import defaultdict, deque
from typing import List, Literal

import httpx
from fastapi import FastAPI, Header, HTTPException, Request
from fastapi.exceptions import RequestValidationError
from starlette.exceptions import HTTPException as StarletteHTTPException
from fastapi.responses import JSONResponse, StreamingResponse
from pydantic import BaseModel, Field, field_validator


import json
# ============================================================
# Logging
# ============================================================

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)s | %(message)s",
)

logger = logging.getLogger("llm-gateway")


# ============================================================
# Application
# ============================================================

app = FastAPI(
    title="LLM Gateway",
    description="OpenAI-compatible LLM Gateway",
    version="0.4.0",
)


# ============================================================
# Standard Error Handling
# ============================================================

# ============================================================
# Standard Error Handling
# ============================================================

@app.exception_handler(StarletteHTTPException)
async def starlette_http_exception_handler(
    request: Request,
    exc: StarletteHTTPException,
):
    request_id = getattr(
        request.state,
        "request_id",
        str(uuid.uuid4()),
    )

    if exc.status_code == 405:
        error_type = "invalid_request_error"
        error_code = "method_not_allowed"
    elif exc.status_code == 404:
        error_type = "not_found_error"
        error_code = "not_found"
    else:
        error_type = "api_error"
        error_code = "api_error"

    response = JSONResponse(
        status_code=exc.status_code,
        content={
            "error": {
                "message": str(exc.detail),
                "type": error_type,
                "code": error_code,
            }
        },
    )

    response.headers["X-Request-ID"] = request_id

    return response



@app.exception_handler(HTTPException)
async def http_exception_handler(
    request: Request,
    exc: HTTPException,
):
    request_id = getattr(
        request.state,
        "request_id",
        str(uuid.uuid4()),
    )

    error_type = "api_error"
    error_code = "api_error"

    if exc.status_code in (401, 403):
        error_type = "authentication_error"
        error_code = "invalid_api_key"
    elif exc.status_code == 404:
        error_type = "not_found_error"
        error_code = "not_found"
    elif exc.status_code == 429:
        error_type = "rate_limit_error"
        error_code = "rate_limit_exceeded"
    elif exc.status_code >= 500:
        error_type = "server_error"
        error_code = "internal_error"

    response = JSONResponse(
        status_code=exc.status_code,
        content={
            "error": {
                "message": str(exc.detail),
                "type": error_type,
                "code": error_code,
            }
        },
    )

    response.headers["X-Request-ID"] = request_id

    return response


# ============================================================
# Validation Error Handling
# ============================================================

@app.exception_handler(RequestValidationError)
async def validation_exception_handler(
    request: Request,
    exc: RequestValidationError,
):
    request_id = getattr(
        request.state,
        "request_id",
        str(uuid.uuid4()),
    )

    logger.warning(
        "request_id=%s validation_error=%s",
        request_id,
        exc.errors(),
    )

    response = JSONResponse(
        status_code=422,
        content={
            "error": {
                "message": "Invalid request parameters",
                "type": "invalid_request_error",
                "code": "validation_error",
            }
        },
    )

    response.headers["X-Request-ID"] = request_id

    return response



# ============================================================
# Configuration
# ============================================================

LLM_BACKEND_URL = os.getenv(
    "LLM_BACKEND_URL",
    "http://llm-backend:8080",
)

API_KEYS_RAW = os.getenv("API_KEYS", "")

DEFAULT_RATE_LIMIT = int(
    os.getenv("RATE_LIMIT_REQUESTS", "60")
)

RATE_LIMIT_WINDOW = int(
    os.getenv("RATE_LIMIT_WINDOW", "60")
)


BACKEND_CONNECT_TIMEOUT = float(
    os.getenv(
        "BACKEND_CONNECT_TIMEOUT",
        "5",
    )
)

BACKEND_READ_TIMEOUT = float(
    os.getenv(
        "BACKEND_READ_TIMEOUT",
        "300",
    )
)

BACKEND_WRITE_TIMEOUT = float(
    os.getenv(
        "BACKEND_WRITE_TIMEOUT",
        "30",
    )
)

BACKEND_POOL_TIMEOUT = float(
    os.getenv(
        "BACKEND_POOL_TIMEOUT",
        "5",
    )
)


# ============================================================
# HTTP Client Timeout
# ============================================================

BACKEND_TIMEOUT = httpx.Timeout(
    connect=BACKEND_CONNECT_TIMEOUT,
    read=BACKEND_READ_TIMEOUT,
    write=BACKEND_WRITE_TIMEOUT,
    pool=BACKEND_POOL_TIMEOUT,
)



# ============================================================
# API Key Management
# ============================================================

def load_api_keys():
    """
    Format:

    API_KEYS=key:name:limit:enabled,key:name:limit:enabled

    Example:

    API_KEYS=your_api_key:developer:60:true,
    another_api_key:tester:20:true
    """

    keys = {}

    if not API_KEYS_RAW:
        return keys

    for item in API_KEYS_RAW.split(","):

        item = item.strip()

        if not item:
            continue

        parts = item.split(":")

        if len(parts) != 4:
            logger.warning(
                "Invalid API key configuration"
            )
            continue

        key, name, rate_limit, enabled = parts

        try:
            rate_limit = int(rate_limit)
        except ValueError:
            logger.warning(
                "Invalid rate limit for key=%s",
                name,
            )
            continue

        enabled = enabled.lower() == "true"

        keys[key] = {
            "name": name,
            "rate_limit": rate_limit,
            "enabled": enabled,
        }

    return keys


API_KEYS = load_api_keys()


# ============================================================
# Rate Limiter
# ============================================================

request_history = defaultdict(deque)


def check_rate_limit(
    api_key: str,
    rate_limit: int,
):

    now = time.time()

    history = request_history[api_key]

    while history and history[0] <= now - RATE_LIMIT_WINDOW:
        history.popleft()

    current_count = len(history)

    if current_count >= rate_limit:

        reset_at = int(
            history[0] + RATE_LIMIT_WINDOW
        )

        return {
            "allowed": False,
            "limit": rate_limit,
            "remaining": 0,
            "reset": reset_at,
        }

    history.append(now)

    remaining = rate_limit - len(history)

    reset_at = int(
        now + RATE_LIMIT_WINDOW
    )

    return {
        "allowed": True,
        "limit": rate_limit,
        "remaining": remaining,
        "reset": reset_at,
    }


# ============================================================
# Request ID Middleware
# ============================================================

@app.middleware("http")
async def request_id_middleware(
    request: Request,
    call_next,
):

    request_id = request.headers.get(
        "X-Request-ID"
    ) or str(uuid.uuid4())

    request.state.request_id = request_id

    start_time = time.perf_counter()

    logger.info(
        "request_id=%s method=%s path=%s started",
        request_id,
        request.method,
        request.url.path,
    )

    try:

        response = await call_next(request)

    except Exception:

        duration_ms = (
            time.perf_counter() - start_time
        ) * 1000

        logger.exception(
            "request_id=%s method=%s path=%s "
            "status=500 duration_ms=%.2f",
            request_id,
            request.method,
            request.url.path,
            duration_ms,
        )

        raise

    duration_ms = (
        time.perf_counter() - start_time
    ) * 1000

    response.headers["X-Request-ID"] = request_id

    logger.info(
        "request_id=%s method=%s path=%s "
        "status=%s duration_ms=%.2f",
        request_id,
        request.method,
        request.url.path,
        response.status_code,
        duration_ms,
    )

    return response


# ============================================================
# Authentication + Rate Limiting
# ============================================================

def extract_api_key(
    x_api_key: str | None,
    authorization: str | None,
) -> str | None:

    if x_api_key:
        return x_api_key

    if authorization:
        scheme, _, credentials = authorization.partition(" ")

        if scheme.lower() == "bearer" and credentials:
            return credentials

    return None


def authenticate_and_rate_limit(
    x_api_key: str | None,
    request: Request,
):

    request_id = request.state.request_id

    if not x_api_key:

        logger.warning(
            "request_id=%s authentication_failed "
            "reason=missing_api_key",
            request_id,
        )

        raise HTTPException(
            status_code=401,
            detail="Invalid or missing API key",
        )

    key_config = API_KEYS.get(x_api_key)

    if not key_config:

        logger.warning(
            "request_id=%s authentication_failed "
            "reason=invalid_api_key",
            request_id,
        )

        raise HTTPException(
            status_code=401,
            detail="Invalid or missing API key",
        )

    if not key_config["enabled"]:

        logger.warning(
            "request_id=%s authentication_failed "
            "reason=disabled_api_key name=%s",
            request_id,
            key_config["name"],
        )

        raise HTTPException(
            status_code=403,
            detail="API key is disabled",
        )

    rate = check_rate_limit(
        x_api_key,
        key_config["rate_limit"],
    )

    if not rate["allowed"]:

        logger.warning(
            "request_id=%s rate_limit_exceeded "
            "name=%s limit=%s reset=%s",
            request_id,
            key_config["name"],
            rate["limit"],
            rate["reset"],
        )

        response = JSONResponse(
            status_code=429,
            content={
                "error": {
                    "message": "Rate limit exceeded",
                    "type": "rate_limit_error",
                    "code": "rate_limit_exceeded",
                }
            },
        )

        response.headers[
            "X-RateLimit-Limit"
        ] = str(rate["limit"])

        response.headers[
            "X-RateLimit-Remaining"
        ] = "0"

        response.headers[
            "X-RateLimit-Reset"
        ] = str(rate["reset"])

        response.headers[
            "Retry-After"
        ] = str(
            max(
                1,
                rate["reset"] - int(time.time()),
            )
        )

        response.headers[
            "X-Request-ID"
        ] = request_id

        return response

    return {
        **rate,
        "name": key_config["name"],
    }


# ============================================================
# Request Models
# ============================================================

class ChatMessage(BaseModel):
    role: Literal["system", "user", "assistant"]
    content: str

    @field_validator("content")
    @classmethod
    def validate_content(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("Message content cannot be empty")
        return value


class ChatCompletionRequest(BaseModel):
    model: str
    messages: List[ChatMessage] = Field(min_length=1)
    temperature: float = Field(default=0.7, ge=0.0, le=2.0)
    max_tokens: int = Field(default=256, ge=1, le=4096)
    stream: bool = False

    @field_validator("model")
    @classmethod
    def validate_model(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("Model cannot be empty")
        return value


# ============================================================
# Health
# ============================================================

@app.get("/health")
async def health():

    return {
        "status": "ok"
    }


# ============================================================
# Readiness
# ============================================================

@app.get("/ready")
async def ready(
    request: Request,
):

    request_id = request.state.request_id

    try:

        async with httpx.AsyncClient(
            timeout=3.0
        ) as client:

            response = await client.get(
                f"{LLM_BACKEND_URL}/health"
            )

        if response.status_code >= 400:

            logger.warning(
                "request_id=%s readiness_failed "
                "backend_status=%s",
                request_id,
                response.status_code,
            )

            result = JSONResponse(
                status_code=503,
                content={
                    "status": "not_ready",
                    "backend": "unavailable",
                },
            )

            result.headers[
                "X-Request-ID"
            ] = request_id

            return result

        logger.info(
            "request_id=%s readiness_ok",
            request_id,
        )

        result = JSONResponse(
            status_code=200,
            content={
                "status": "ready",
                "backend": "ok",
            },
        )

        result.headers[
            "X-Request-ID"
        ] = request_id

        return result

    except httpx.HTTPError as exc:

        logger.error(
            "request_id=%s readiness_error "
            "error=%s",
            request_id,
            str(exc),
        )

        result = JSONResponse(
            status_code=503,
            content={
                "status": "not_ready",
                "backend": "unavailable",
            },
        )

        result.headers[
            "X-Request-ID"
        ] = request_id

        return result


# ============================================================
# Models
# ============================================================

MODEL_MAP = {
    "qwen-local": "/models/qwen2.5-0.5b-instruct-q4_k_m.gguf"
}


@app.get("/v1/models")
async def models(
    request: Request,
    x_api_key: str | None = Header(
        default=None,
        alias="X-API-Key",
    ),
    authorization: str | None = Header(
        default=None,
        alias="Authorization",
    ),
):

    api_key = extract_api_key(
        x_api_key,
        authorization,
    )

    auth_result = authenticate_and_rate_limit(
        api_key,
        request,
    )

    if isinstance(
        auth_result,
        JSONResponse,
    ):
        return auth_result

    response = JSONResponse(
        content={
            "object": "list",
            "data": [
                {
                    "id": model_id,
                    "object": "model",
                    "owned_by": "local",
                }
                for model_id in MODEL_MAP
            ],
        }
    )

    response.headers[
        "X-RateLimit-Limit"
    ] = str(auth_result["limit"])

    response.headers[
        "X-RateLimit-Remaining"
    ] = str(auth_result["remaining"])

    response.headers[
        "X-RateLimit-Reset"
    ] = str(auth_result["reset"])

    return response


# ============================================================
# Chat Completions
# ============================================================

@app.post("/v1/chat/completions")
async def chat_completions(
    payload: ChatCompletionRequest,
    request: Request,
    x_api_key: str | None = Header(
        default=None,
        alias="X-API-Key",
    ),
    authorization: str | None = Header(
        default=None,
        alias="Authorization",
    ),
):

    api_key = extract_api_key(
        x_api_key,
        authorization,
    )

    auth_result = authenticate_and_rate_limit(
        api_key,
        request,
    )

    if isinstance(
        auth_result,
        JSONResponse,
    ):
        return auth_result

    request_id = request.state.request_id

    if payload.model not in MODEL_MAP:

        logger.warning(
            "request_id=%s unknown_model=%s",
            request_id,
            payload.model,
        )

        raise HTTPException(
            status_code=404,
            detail=f"Unknown model: {payload.model}",
        )

    logger.info(
        "request_id=%s api_key_name=%s "
        "model=%s stream=%s max_tokens=%s",
        request_id,
        auth_result["name"],
        payload.model,
        payload.stream,
        payload.max_tokens,
    )

    backend_payload = {
        "model": MODEL_MAP[payload.model],
        "messages": [
            {
                "role": message.role,
                "content": message.content,
            }
            for message in payload.messages
        ],
        "temperature": payload.temperature,
        "max_tokens": payload.max_tokens,
        "stream": payload.stream,
    }

    if payload.stream:

        timeout = httpx.Timeout(
            connect=BACKEND_CONNECT_TIMEOUT,
            read=BACKEND_READ_TIMEOUT,
            write=BACKEND_WRITE_TIMEOUT,
            pool=BACKEND_POOL_TIMEOUT,
        )

        client = httpx.AsyncClient(timeout=timeout)

        try:

            request_to_backend = client.build_request(
                "POST",
                f"{LLM_BACKEND_URL}/v1/chat/completions",
                json=backend_payload,
            )

            backend_response = await client.send(
                request_to_backend,
                stream=True,
            )

        except httpx.ConnectTimeout as exc:

            await client.aclose()

            logger.error(
                "request_id=%s "
                "backend_stream_connect_timeout "
                "error=%s",
                request_id,
                str(exc),
            )

            raise HTTPException(
                status_code=502,
                detail="Unable to connect to LLM backend",
            )

        except httpx.ConnectError as exc:

            await client.aclose()

            logger.error(
                "request_id=%s "
                "backend_stream_connect_error "
                "error=%s",
                request_id,
                str(exc),
            )

            raise HTTPException(
                status_code=502,
                detail="Unable to connect to LLM backend",
            )

        except httpx.HTTPError as exc:

            await client.aclose()

            logger.error(
                "request_id=%s "
                "backend_stream_http_error "
                "error=%s",
                request_id,
                str(exc),
            )

            raise HTTPException(
                status_code=502,
                detail="Unable to connect to LLM backend",
            )

        except Exception as exc:

            await client.aclose()

            logger.exception(
                "request_id=%s "
                "backend_stream_unexpected_error",
                request_id,
            )

            raise HTTPException(
                status_code=502,
                detail="Unable to connect to LLM backend",
            )

        # --------------------------------------------------------
        # Backend returned HTTP error before streaming started
        # --------------------------------------------------------

        if backend_response.status_code >= 400:

            body = await backend_response.aread()

            await backend_response.aclose()
            await client.aclose()

            logger.error(
                "request_id=%s "
                "backend_stream_backend_error "
                "status=%s "
                "body=%s",
                request_id,
                backend_response.status_code,
                body.decode(errors="replace"),
            )

            raise HTTPException(
                status_code=502,
                detail="LLM backend returned an error",
            )

        # --------------------------------------------------------
        # Stream parser
        #
        # Backend sends SSE events like:
        #
        # data: {...}
        #
        # data: {...}
        #
        # data: [DONE]
        #
        # TCP chunks are not guaranteed to match SSE events,
        # therefore we keep a byte buffer and split on blank lines.
        # Both LF and CRLF are supported.
        # --------------------------------------------------------

        async def stream_response():

            buffer = b""

            try:

                async for chunk in backend_response.aiter_bytes():

                    if not chunk:
                        continue

                    buffer += chunk

                    # Normalize CRLF / CR to LF.
                    buffer = buffer.replace(
                        b"\r\n",
                        b"\n",
                    ).replace(
                        b"\r",
                        b"\n",
                    )

                    while b"\n\n" in buffer:

                        raw_event, buffer = buffer.split(
                            b"\n\n",
                            1,
                        )

                        if not raw_event.strip():
                            continue

                        # ------------------------------------------------
                        # SSE event parser
                        #
                        # IMPORTANT:
                        # bytes.splitlines() returns bytes objects.
                        # We explicitly verify the type before using
                        # string/bytes methods.
                        # ------------------------------------------------

                        for raw_line in raw_event.split(b"\n"):

                            if not isinstance(raw_line, bytes):
                                logger.warning(
                                    "request_id=%s "
                                    "backend_stream_invalid_line_type=%s",
                                    request_id,
                                    type(raw_line).__name__,
                                )
                                continue

                            raw_line = raw_line.strip()

                            if not raw_line:
                                continue

                            # We only expose SSE data fields.
                            if not raw_line.startswith(b"data:"):
                                continue

                            data = raw_line[len(b"data:"):].strip()

                            # ------------------------------------------------
                            # OpenAI-compatible termination
                            # ------------------------------------------------

                            if data == b"[DONE]":

                                yield (
                                    b"data: [DONE]\n\n"
                                )

                                continue

                            # ------------------------------------------------
                            # Parse JSON
                            # ------------------------------------------------

                            try:

                                obj = json.loads(
                                    data.decode("utf-8")
                                )

                            except (
                                json.JSONDecodeError,
                                UnicodeDecodeError,
                            ):

                                logger.warning(
                                    "request_id=%s "
                                    "backend_stream_invalid_json",
                                    request_id,
                                )

                                continue

                            # ------------------------------------------------
                            # Normalize public model name
                            # ------------------------------------------------

                            obj["model"] = payload.model

                            # ------------------------------------------------
                            # Remove backend-specific llama.cpp timings
                            #
                            # OpenAI-compatible clients should not need
                            # backend-specific timing metadata.
                            # ------------------------------------------------

                            obj.pop("timings", None)

                            # ------------------------------------------------
                            # Ensure OpenAI-compatible object type
                            # ------------------------------------------------

                            if "object" not in obj:
                                obj["object"] = "chat.completion.chunk"

                            # ------------------------------------------------
                            # Serialize compact JSON
                            # ------------------------------------------------

                            normalized = json.dumps(
                                obj,
                                ensure_ascii=False,
                                separators=(",", ":"),
                            ).encode("utf-8")

                            yield (
                                b"data: "
                                + normalized
                                + b"\n\n"
                            )

                # --------------------------------------------------------
                # Flush final buffered SSE event
                # --------------------------------------------------------

                if buffer.strip():

                    buffer = buffer.replace(
                        b"\r\n",
                        b"\n",
                    ).replace(
                        b"\r",
                        b"\n",
                    )

                    for raw_line in buffer.split(b"\n"):

                        if not isinstance(raw_line, bytes):
                            continue

                        raw_line = raw_line.strip()

                        if not raw_line:
                            continue

                        if not raw_line.startswith(b"data:"):
                            continue

                        data = raw_line[len(b"data:"):].strip()

                        if data == b"[DONE]":

                            yield (
                                b"data: [DONE]\n\n"
                            )

                            continue

                        try:

                            obj = json.loads(
                                data.decode("utf-8")
                            )

                        except (
                            json.JSONDecodeError,
                            UnicodeDecodeError,
                        ):

                            logger.warning(
                                "request_id=%s "
                                "backend_stream_invalid_final_json",
                                request_id,
                            )

                            continue

                        obj["model"] = payload.model
                        obj.pop("timings", None)

                        if "object" not in obj:
                            obj["object"] = "chat.completion.chunk"

                        normalized = json.dumps(
                            obj,
                            ensure_ascii=False,
                            separators=(",", ":"),
                        ).encode("utf-8")

                        yield (
                            b"data: "
                            + normalized
                            + b"\n\n"
                        )

                logger.info(
                    "request_id=%s "
                    "backend_stream_success "
                    "model=%s",
                    request_id,
                    payload.model,
                )

            except httpx.ReadTimeout as exc:

                logger.error(
                    "request_id=%s "
                    "backend_stream_read_timeout "
                    "error=%s",
                    request_id,
                    str(exc),
                )

            except httpx.HTTPError as exc:

                logger.error(
                    "request_id=%s "
                    "backend_stream_http_error "
                    "error=%s",
                    request_id,
                    str(exc),
                )

            except Exception:

                logger.exception(
                    "request_id=%s "
                    "backend_stream_unexpected_error",
                    request_id,
                )

            finally:

                await backend_response.aclose()
                await client.aclose()

        response = StreamingResponse(
            stream_response(),
            media_type="text/event-stream",
        )

        response.headers[
            "X-Request-ID"
        ] = request_id

        response.headers[
            "X-RateLimit-Limit"
        ] = str(auth_result["limit"])

        response.headers[
            "X-RateLimit-Remaining"
        ] = str(auth_result["remaining"])

        response.headers[
            "X-RateLimit-Reset"
        ] = str(auth_result["reset"])

        response.headers[
            "Cache-Control"
        ] = "no-cache"

        response.headers[
            "X-Accel-Buffering"
        ] = "no"

        return response

    try:

        async with httpx.AsyncClient(
            timeout=BACKEND_TIMEOUT
        ) as client:

            response = await client.post(
                f"{LLM_BACKEND_URL}/v1/chat/completions",
                json=backend_payload,
            )

        if response.status_code >= 400:

            logger.error(
                "request_id=%s backend_http_error "
                "status=%s body=%s",
                request_id,
                response.status_code,
                response.text[:1000],
            )

            raise HTTPException(
                status_code=502,
                detail="LLM backend returned an error",
            )

        try:
            data = response.json()
        except ValueError:

            logger.error(
                "request_id=%s backend_invalid_json",
                request_id,
            )

            raise HTTPException(
                status_code=502,
                detail="Invalid response from LLM backend",
            )

        data["model"] = payload.model

        logger.info(
            "request_id=%s backend_success "
            "model=%s",
            request_id,
            payload.model,
        )

        result = JSONResponse(
            content=data
        )

        result.headers[
            "X-RateLimit-Limit"
        ] = str(auth_result["limit"])

        result.headers[
            "X-RateLimit-Remaining"
        ] = str(auth_result["remaining"])

        result.headers[
            "X-RateLimit-Reset"
        ] = str(auth_result["reset"])

        return result

    except httpx.TimeoutException as exc:

        logger.error(
            "request_id=%s backend_timeout "
            "error=%s",
            request_id,
            str(exc),
        )

        raise HTTPException(
            status_code=502,
            detail="LLM backend request timed out",
        )

    except httpx.ConnectError as exc:

        logger.error(
            "request_id=%s backend_connection_error "
            "error=%s",
            request_id,
            str(exc),
        )

        raise HTTPException(
            status_code=502,
            detail="Unable to connect to LLM backend",
        )

    except httpx.HTTPError as exc:

        logger.error(
            "request_id=%s backend_http_error "
            "error=%s",
            request_id,
            str(exc),
        )

        raise HTTPException(
            status_code=502,
            detail="LLM backend communication error",
        )
