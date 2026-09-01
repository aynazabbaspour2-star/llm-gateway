# 🌈 LLM Gateway

### Production-Minded OpenAI-Compatible Gateway for Local LLMs

A lightweight, secure, resilient and testable gateway for local Large Language Model inference.

![Python](https://img.shields.io/badge/Python-3.12-3776AB?style=for-the-badge&logo=python&logoColor=white)
![FastAPI](https://img.shields.io/badge/FastAPI-0.115.6-009688?style=for-the-badge&logo=fastapi&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-Compose-2496ED?style=for-the-badge&logo=docker&logoColor=white)
![llama.cpp](https://img.shields.io/badge/llama.cpp-Local%20Inference-FF69B4?style=for-the-badge)
![Qwen](https://img.shields.io/badge/Qwen-GGUF-7C3AED?style=for-the-badge)
![Security](https://img.shields.io/badge/Security-API%20Keys-success?style=for-the-badge)
![Rate%20Limiting](https://img.shields.io/badge/Rate%20Limiting-Enabled-orange?style=for-the-badge)
![Streaming](https://img.shields.io/badge/Streaming-Supported-blue?style=for-the-badge)
![Testing](https://img.shields.io/badge/Testing-Automated-success?style=for-the-badge)

---

## 🧠 Overview

**LLM Gateway** is a production-minded API gateway designed to provide a secure and reliable interface for serving local Large Language Models.

The gateway exposes an **OpenAI-compatible API** while adding infrastructure-level capabilities such as:

- API key authentication
- Per-key rate limiting
- Strict request validation
- Structured error contracts
- Request ID propagation
- Streaming responses
- Health and readiness checks
- Backend timeout control
- Backend failure and recovery handling
- Concurrent request handling
- Automated reliability and security testing
- Docker Compose deployment

The project focuses on **reliability, security, observability and operational behavior**, rather than only exposing an inference endpoint.

---

## 🏗️ Architecture

```text
Client
  |
  v
+-----------------------------+
|        LLM Gateway          |
|           FastAPI           |
+-----------------------------+
  |
  +-- API Key Authentication
  |
  +-- Rate Limiting
  |
  +-- Request Validation
  |
  +-- Request IDs
  |
  +-- Error Handling
  |
  +-- Timeout Management
  |
  v
+-----------------------------+
|          llama.cpp          |
|       Inference Server      |
+-----------------------------+
  |
  v
+-----------------------------+
|      Qwen 2.5 0.5B          |
|        GGUF Model           |
+-----------------------------+
Request Flow
Client
  |
  v
LLM Gateway
  |
  +--> Authentication
  |
  +--> Rate Limiting
  |
  +--> Validation
  |
  +--> Backend Request
          |
          v
      llama.cpp
          |
          v
      Qwen GGUF
✨ Features
Area	Capability
Authentication	API-key based authentication
Rate Limiting	Per-key request limits
Validation	Strict request validation
Chat API	OpenAI-compatible chat completion endpoint
Streaming	Streaming chat responses
Models	Model discovery endpoint
Health	Health and readiness endpoints
Errors	Structured OpenAI-style error responses
Request IDs	Request correlation through headers
Resilience	Backend failure and recovery handling
Timeouts	Connect, read, write and pool timeouts
Concurrency	Concurrent request handling
Testing	Security, validation, regression and reliability suites
Docker	Docker + Docker Compose deployment
📡 API Endpoints
Method	Endpoint	Description
GET	/health	Gateway health check
GET	/ready	Gateway and backend readiness
GET	/v1/models	List available models
POST	/v1/chat/completions	Generate chat completions
💬 Chat Completions

The gateway exposes an OpenAI-compatible chat completion endpoint.

Non-Streaming Request
curl http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "X-API-Key: YOUR_API_KEY" \
  -d '{
    "model": "qwen2.5-0.5b-instruct",
    "messages": [
      {
        "role": "user",
        "content": "Hello!"
      }
    ],
    "temperature": 0.7,
    "max_tokens": 128
  }'
Streaming Request
curl -N http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "X-API-Key: YOUR_API_KEY" \
  -d '{
    "model": "qwen2.5-0.5b-instruct",
    "messages": [
      {
        "role": "user",
        "content": "Explain Docker in simple terms."
      }
    ],
    "stream": true
  }'
🔐 Authentication

The gateway uses API keys supplied through environment variables.

API keys follow this format:

key:name:rate_limit:enabled

Example:

API_KEYS=your_api_key:developer:60:true

Clients send the API key using:

X-API-Key: YOUR_API_KEY

Example:

curl http://localhost:8000/v1/models \
  -H "X-API-Key: YOUR_API_KEY"

Real credentials are intentionally excluded from Git.

Use .env for local credentials and .env.example as the repository-safe configuration template.

🚦 Rate Limiting

Rate limiting is applied per API key.

Example:

RATE_LIMIT_WINDOW=60
API_KEYS=your_api_key:developer:60:true

The gateway exposes rate-limit information through response headers and returns:

429 Too Many Requests

when the configured limit is exceeded.

The rate-limit error follows the gateway's structured error contract.

🧾 Error Contract

The gateway provides consistent JSON error responses across authentication, validation, routing and backend failures.

Example:

{
  "error": {
    "message": "Invalid API key",
    "type": "authentication_error",
    "code": "invalid_api_key"
  }
}

Supported error scenarios include:

Missing API key
Invalid API key
Disabled API key
Unknown model
Invalid request body
Invalid message format
Unsupported HTTP method
Rate limit exceeded
Backend unavailable
Backend timeout
Backend streaming failure
🛡️ Request Validation

The API validates incoming requests before forwarding them to the inference backend.

Validation covers:

Request body structure
Message structure
Message roles
Message content
Model selection
Temperature
Maximum token limits
Streaming configuration
Invalid data types
Missing required fields

Invalid requests return HTTP 422.

🌊 Streaming

The gateway supports streaming responses for chat completions.

Streaming is implemented as an HTTP streaming response and is tested independently from standard non-streaming requests.

The test suite also covers failure scenarios involving backend interruptions during streaming.

❤️ Health & Readiness
Health
GET /health

Checks whether the gateway process is running.

Readiness
GET /ready

Checks whether the gateway and inference backend are ready to serve requests.

This distinction allows infrastructure systems to differentiate between:

Process availability
Service readiness
Backend availability
⏱️ Backend Timeouts

Backend communication uses separate timeout controls:

BACKEND_CONNECT_TIMEOUT=5
BACKEND_READ_TIMEOUT=300
BACKEND_WRITE_TIMEOUT=30
BACKEND_POOL_TIMEOUT=5

This provides explicit control over:

Connection establishment
Response reading
Request writing
Connection pool acquisition

The project also includes real timeout testing against the backend.

🔄 Resilience & Failure Handling

The gateway is designed to handle backend failures without requiring a gateway restart.

Tested scenarios include:

Backend unavailable
Backend recovery
Streaming backend failure
Mid-stream disconnect
Backend timeout
Concurrent requests
Post-recovery requests

The regression suite verifies that the gateway returns to normal operation after backend recovery.

🧪 Testing

The project includes dedicated test scripts for different reliability dimensions.

Script	Purpose
validation_test.sh	Request validation
validation_error_test.sh	Validation error contracts
security_test.sh	Authentication and security behavior
concurrent_test.sh	Concurrent request behavior
error_contract_test.sh	Error response contracts
regression_test.sh	Full reliability and recovery regression
Python Syntax
python3 -m py_compile app/main.py fault_proxy.py
Shell Syntax
bash -n concurrent_test.sh
bash -n error_contract_test.sh
bash -n regression_test.sh
bash -n security_test.sh
bash -n validation_error_test.sh
bash -n validation_test.sh
Error Contract Result
ERROR CONTRACT SUMMARY
PASS : 7
FAIL : 0
ERROR CONTRACT RESULT: PASS

The regression suite additionally covers backend failure, timeout, streaming interruption, concurrency and recovery scenarios.
Docker

The project is designed to run as a two-service Docker Compose stack.

llm-backend
    |
    +-- llama.cpp inference server
    |
    +-- Qwen GGUF model

gateway
    |
    +-- FastAPI LLM Gateway

The gateway waits for the backend health check before normal service operation.

⚙️ Configuration

Create the local environment file:

cp .env.example .env

Example configuration:

API_KEYS=your_api_key:developer:60:true

RATE_LIMIT_WINDOW=60

LLM_BACKEND_URL=http://llm-backend:8080

BACKEND_CONNECT_TIMEOUT=5
BACKEND_READ_TIMEOUT=300
BACKEND_WRITE_TIMEOUT=30
BACKEND_POOL_TIMEOUT=5
🧠 Local Model

The default local inference backend uses:

Qwen 2.5 0.5B Instruct

in GGUF format through llama.cpp.

The model file is intentionally excluded from Git because model binaries can be large.

Expected local model path:

models/
└── qwen2.5-0.5b-instruct-q4_k_m.gguf

The repository contains the infrastructure required to run the model but does not include the model binary itself.

📁 Project Structure
llm-gateway/
|
├── app/
|   ├── __init__.py
|   └── main.py
|
├── models/
|   └── qwen2.5-0.5b-instruct-q4_k_m.gguf
|
├── concurrent_test.sh
├── error_contract_test.sh
├── regression_test.sh
├── security_test.sh
├── validation_error_test.sh
├── validation_test.sh
|
├── fault_proxy.py
|
├── docker-compose.yml
├── Dockerfile
├── requirements.txt
|
├── .env.example
├── .gitignore
└── README.md

The model file is local-only and is not tracked by Git.

🧰 Tech Stack
Python 3.12
FastAPI
Uvicorn
HTTPX
Pydantic v2
Docker
Docker Compose
llama.cpp
Qwen 2.5
GGUF
Bash
Git / GitHub
🎯 Engineering Focus

This project was built with an infrastructure and backend engineering mindset.

Security
API key authentication
Disabled-key handling
Input validation
No credentials committed to Git
Reliability
Backend health checks
Readiness checks
Explicit timeout configuration
Failure and recovery handling
Streaming failure testing
API Design
OpenAI-compatible interface
Structured errors
Consistent HTTP status codes
Request IDs
Predictable validation behavior
Testing
Dedicated security tests
Validation tests
Error contract tests
Concurrency tests
Regression testing
Failure injection
Recovery verification
Operations
Dockerized deployment
Environment-based configuration
Health checks
Service dependencies
Local inference infrastructure
🚀 Quick Start
1. Clone the repository
git clone https://github.com/aynazabbaspour2-star/llm-gateway.git
cd llm-gateway
2. Configure environment
cp .env.example .env

Edit .env and configure your API key.

3. Add the local model

Place the GGUF model at:

models/qwen2.5-0.5b-instruct-q4_k_m.gguf
4. Start the stack
docker compose up --build
5. Check health
curl http://localhost:8000/health
6. Check readiness
curl http://localhost:8000/ready
7. List models
curl http://localhost:8000/v1/models \
  -H "X-API-Key: YOUR_API_KEY"
🗺️ Roadmap
 Prometheus metrics
 Structured application logging
 Distributed rate limiting
 Redis-backed state
 Multiple backend support
 Load balancing
 API key management API
 OpenTelemetry tracing
 GitHub Actions CI/CD
 Kubernetes deployment
 Production-grade observability
 Multi-model routing
💡 Why This Project?

Local LLM inference is only one part of building a usable AI service.

A production-facing AI API also needs:

Authentication
      +
Validation
      +
Rate Limiting
      +
Timeouts
      +
Error Handling
      +
Streaming
      +
Health Checks
      +
Failure Recovery
      +
Testing
      =
Reliable AI Service

This project demonstrates how an inference engine can be wrapped with the infrastructure required to expose it as a more reliable API service.

📌 Project Status

The current implementation is functional and tested locally.

The project is intentionally designed as a foundation that can evolve toward:

Multi-model serving
Distributed infrastructure
Observability
Scalable deployment
Production-oriented AI gateway architecture
<div align="center">
🌈 LLM Gateway

Secure • Reliable • Testable • OpenAI-Compatible

Built with Python, FastAPI, Docker and Local AI.

</div>