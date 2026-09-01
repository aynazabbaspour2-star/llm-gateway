# 🌈 LLM Gateway

<p align="center">
  <strong>A production-minded, OpenAI-compatible gateway for local LLM inference.</strong><br>
  <strong>یک Gateway سبک، امن و قابل تست برای سرویس‌دهی به مدل‌های زبانی محلی</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Python-3.12-3776AB?style=for-the-badge&logo=python&logoColor=white">
  <img src="https://img.shields.io/badge/FastAPI-0.115.6-009688?style=for-the-badge&logo=fastapi&logoColor=white">
  <img src="https://img.shields.io/badge/Docker-Compose-2496ED?style=for-the-badge&logo=docker&logoColor=white">
  <img src="https://img.shields.io/badge/llama.cpp-Local%20Inference-FF69B4?style=for-the-badge">
  <img src="https://img.shields.io/badge/Qwen-GGUF-7C3AED?style=for-the-badge">
</p>

---

# 🇬🇧 English

                     🤖 Qwen GGUF───────┘l inference backend:ble chat completion
> The project focuses on:

🔐 API security
🛡️ strict request validation
🚦 rate limiting
🌊 streaming responses
⚠️ consistent error contracts
🔄 backend failure and recovery
⏱️ timeout handling
⚡ concurrent requests
🧪 automated reliability testing
🐳 containerized deployment
> 🚀 Features
> | Area              | Capability                                 |
| ----------------- | ------------------------------------------ |
| 🔐 Authentication | API-key based authentication               |
| 🛡️ Validation    | Strict request validation                  |
| 🚦 Rate Limiting  | Per-key request limits                     |
| 💬 Chat API       | OpenAI-compatible chat completion endpoint |
| 🌊 Streaming      | Streaming responses                        |
| 🧠 Models         | Model discovery endpoint                   |
| ❤️ Health         | Health and readiness endpoints             |
| ⚠️ Error Contract | Consistent JSON error responses            |
| 🔄 Resilience     | Backend failure and recovery handling      |
| ⏱️ Timeouts       | Connect / read / write / pool timeouts     |
| ⚡ Concurrency     | Concurrent request handling                |
| 🧪 Testing        | Security, validation and regression suites |
| 🐳 Docker         | Docker + Docker Compose                    |
> 📡 API Endpoints
Method  Endpoint        Description
GET     /health Gateway health check
GET     /ready  Gateway + backend readiness
GET     /v1/models      List available models
POST    /v1/chat/completions    Generate chat completion
> 🔐 Authentication

The Gateway uses API keys supplied through environment variables.

Example:

curl http://localhost:8000/v1/models \
  -H "X-API-Key: YOUR_API_KEY"

API keys are never stored in the repository.

Local credentials belong in:

.env

while the repository only contains:

.env.example
🚦 Rate Limiting

Each API key can have its own request limit.

Example configuration:

API_KEYS=your_api_key:developer:60:true
RATE_LIMIT_WINDOW=60

The Gateway exposes rate-limit information through response headers such as:

ty · DevOpsineering · API Design · Docker · Local LLM Infrastructure · Reliabili
> 
> q
> wq
> q!
> exit
> ^C

Client
  │
  ▼
🌈 LLM Gateway
  │
  ├── 🔐 API Key Authentication
  │
  ├── 🚦 Rate Limiting
  │
  ├── 🛡️ Request Validation
  │
  ├── 🆔 Request ID
  │
  ▼
🤖 llama.cpp Backend
  │
  ▼
🧠 Qwen GGUF Model
  │
  ▼
🌊 Response / Stream
| Area              | Capability                                        |
| ----------------- | ------------------------------------------------- |
| 🔐 Authentication | API-key based authentication                      |
| 🛡️ Validation    | Strict request validation                         |
| 🚦 Rate Limiting  | Per-key request limits                            |
| 💬 Chat API       | OpenAI-compatible chat completions                |
| 🌊 Streaming      | Streaming responses                               |
| 🧠 Models         | Model discovery endpoint                          |
| ❤️ Health         | Health and readiness endpoints                    |
| ⚠️ Error Contract | Consistent structured JSON errors                 |
| 🔄 Resilience     | Backend failure and recovery handling             |
| ⏱️ Timeouts       | Connect / read / write / pool timeouts            |
| ⚡ Concurrency     | Concurrent request handling                       |
| 🆔 Request IDs    | Request tracing support                           |
| 🧪 Testing        | Security, validation, error and regression suites |
| 🐳 Docker         | Docker + Docker Compose deployment                |

| Method | Endpoint               | Description                 |
| ------ | ---------------------- | --------------------------- |
| `GET`  | `/health`              | Gateway health check        |
| `GET`  | `/ready`               | Gateway + backend readiness |
| `GET`  | `/v1/models`           | List available models       |
| `POST` | `/v1/chat/completions` | Generate chat completion    |

curl http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "X-API-Key: YOUR_API_KEY" \
  -d '{
    "model": "qwen2.5-0.5b-instruct",
    "messages": [
      {
        "role": "user",
        "content": "Explain Docker in one sentence."
      }
    ]
  }'
🔐 Authentication

The Gateway uses API keys supplied through environment variables.

Example:

API_KEYS=your_api_key:developer:60:true

API keys follow this format:

key:name:rate_limit:enabled

Example:

my_key:developer:60:true
Field	Meaning
key	API key
name	Key owner / identifier
rate_limit	Maximum requests
enabled	Whether the key is active
🔒 Security

Real credentials should never be committed to Git.

Local secrets belong in:

.env

The repository only contains:

.env.example

The .env file is ignored by Git.

🚦 Rate Limiting

Each API key can have its own request limit.

Example:

API_KEYS=your_api_key:developer:60:true
RATE_LIMIT_WINDOW=60

This configuration allows:

60 requests
per
60 seconds

The Gateway exposes rate-limit information through response headers such as:

X-RateLimit-Limit
X-RateLimit-Remaining
X-RateLimit-Reset

When the limit is exceeded:

HTTP/1.1 429 Too Many Requests

is returned with a structured error response.

⚠️ Error Handling

The Gateway uses a consistent JSON error contract.

Example:

{
  "error": {
    "message": "Invalid API key",
    "type": "authentication_error",
    "code": "invalid_api_key"
  }
}

The implementation covers errors such as:

Status	Scenario
401	Missing or invalid API key
404	Unknown model
405	Unsupported HTTP method
422	Request validation failure
429	Rate limit exceeded
502/503	Backend availability failures
504	Backend timeout
🛡️ Request Validation

The API validates incoming requests before forwarding them to the inference backend.

Validation includes:

Message structure
Message roles
Message content
Model selection
Temperature
Maximum token values
Invalid data types
Missing required fields
Empty messages
Malformed JSON

This prevents invalid requests from unnecessarily reaching the LLM backend.
🌊 Streaming
{
  "model": "qwen2.5-0.5b-instruct",
  "messages": [
    {
      "role": "user",
      "content": "Tell me a short story."
    }
  ],
  "stream": true
}

Streaming responses allow clients to receive generated content incrementally instead of waiting for the entire completion.

❤️ Health & Readiness

Two separate endpoints are provided.

Gateway Health
GET /health

Used to determine whether the Gateway process itself is alive.

Service Readiness
GET /ready

Checks whether the Gateway and its LLM backend are ready to serve requests.

This separation is useful for:

Docker health checks
Container orchestration
Load balancers
Monitoring
Deployment systems
⏱️ Backend Timeouts

Backend communication uses configurable timeout values:

BACKEND_CONNECT_TIMEOUT=5
BACKEND_READ_TIMEOUT=300
BACKEND_WRITE_TIMEOUT=30
BACKEND_POOL_TIMEOUT=5

This prevents the Gateway from hanging indefinitely when the inference backend becomes slow or unavailable.

🔄 Resilience & Failure Handling

The project was designed to test backend failure scenarios rather than only the happy path.

The reliability suite covers scenarios including:

Gateway
   │
   ▼
Backend Healthy
   │
   ├── ✅ Normal request
   ├── 🌊 Streaming request
   │
   ▼
Backend Failure
   │
   ├── ⚠️ Non-stream failure
   ├── ⚠️ Streaming failure
   ├── ⏱️ Backend timeout
   └── 🔌 Mid-stream disconnect
   │
   ▼
Backend Recovery
   │
   ├── ✅ Health restored
   ├── ✅ Normal requests restored
   └── 🌊 Streaming restored
🧪 Testing

The repository contains multiple automated test suites.

Test	Purpose
security_test.sh	Authentication and security validation
validation_test.sh	Request validation
validation_error_test.sh	Invalid request scenarios
error_contract_test.sh	Structured error contract validation
concurrent_test.sh	Concurrent request handling
regression_test.sh	Full reliability and regression testing
🔍 Python Syntax Validation
python3 -m py_compile app/main.py fault_proxy.py
🐚 Shell Syntax Validation
for f in \
  concurrent_test.sh \
  error_contract_test.sh \
  regression_test.sh \
  security_test.sh \
  validation_error_test.sh \
  validation_test.sh
do
  bash -n "$f" && echo "PASS: $f"
done
🧪 Error Contract Test

The error contract suite validates:

Missing API key       → 401
Invalid API key       → 401
Unknown model         → 404
Validation error      → 422
Wrong method          → 405
Rate limit exceeded   → 429

Example result:

ERROR CONTRACT SUMMARY
PASS : 7
FAIL : 0

ERROR CONTRACT RESULT: PASS
The complete stack can be started with Docker Compose.

Build and start
docker compose up -d --build
Check containers
docker compose ps
View logs
docker compose logs -f gateway
Stop the stack
docker compose down
⚙️ Configuration

Create your local environment file:

cp .env.example .env

Then configure:

API_KEYS=your_api_key:developer:60:true

RATE_LIMIT_WINDOW=60

LLM_BACKEND_URL=http://llm-backend:8080

BACKEND_CONNECT_TIMEOUT=5
BACKEND_READ_TIMEOUT=300
BACKEND_WRITE_TIMEOUT=30
BACKEND_POOL_TIMEOUT=5
🤖 Local Model

The project uses a local GGUF model with llama.cpp.

Current model:

Qwen 2.5 0.5B Instruct

Expected local model path:

models/
└── qwen2.5-0.5b-instruct-q4_k_m.gguf

The model file is intentionally not included in Git because model files can be large.

The repository ignores:

models/*.gguf
📁 Project Structure
llm-gateway/
│
├── app/
│   ├── __init__.py
│   └── main.py
│
├── models/
│   └── qwen2.5-0.5b-instruct-q4_k_m.gguf
│
├── concurrent_test.sh
├── error_contract_test.sh
├── regression_test.sh
├── security_test.sh
├── validation_error_test.sh
├── validation_test.sh
│
├── fault_proxy.py
│
├── Dockerfile
├── docker-compose.yml
├── requirements.txt
│
├── .env.example
├── .gitignore
└── README.md

The local GGUF model is ignored by Git and is not part of the repository.

🧰 Tech Stack
Backend






Infrastructure




AI




🎯 Engineering Focus

This project demonstrates practical engineering around:

🐍 Python Backend Development
⚡ FastAPI
🔐 API Authentication
🚦 Rate Limiting
🛡️ Input Validation
🌊 HTTP Streaming
⏱️ Timeout Management
🔄 Failure Recovery
⚡ Concurrent Requests
🧪 Automated Testing
🐳 Docker
🤖 Local LLM Infrastructure
🔌 OpenAI-Compatible APIs
❤️ Health / Readiness Checks
🆔 Request Tracing
🚀 Quick Start
1️⃣ Clone the repository
git clone https://github.com/aynazabbaspour2-star/llm-gateway.git
cd llm-gateway
2️⃣ Configure environment
cp .env.example .env
3️⃣ Add the local model

Place the GGUF model inside:

models/
4️⃣ Start the stack
docker compose up -d --build
5️⃣ Check health
curl http://localhost:8000/health
6️⃣ Check readiness
curl http://localhost:8000/ready
7️⃣ List available models
curl http://localhost:8000/v1/models \
  -H "X-API-Key: YOUR_API_KEY"
8️⃣ Send a chat request
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
    ]
  }'
🗺️ Roadmap

Potential future improvements:

 Persistent API-key storage
 Redis-based distributed rate limiting
 Prometheus metrics
 Grafana dashboards
 Structured application logging
 Distributed tracing
 Multiple LLM backend support
 Load balancing between inference servers
 API key management UI
 Kubernetes deployment
 CI/CD pipeline
 Automated integration environment
🌟 Why This Project?

LLM applications are not only about calling a model.

A production-ready AI service also needs:

🔐 Security
🛡️ Validation
🚦 Traffic Control
⏱️ Timeout Management
❤️ Health Monitoring
🔄 Failure Recovery
🧪 Automated Testing
🐳 Deployment
📊 Observability

LLM Gateway focuses on these engineering concerns around local LLM inference.

<div align="center">
💜 Built with Python, FastAPI, Docker & Local AI
🌈 LLM Gateway

Secure • Reliable • Testable • OpenAI-Compatible

</div>

