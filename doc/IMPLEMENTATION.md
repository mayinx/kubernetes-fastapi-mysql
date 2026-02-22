

# docs/IMPLEMENTATION.md — Kubernetes Exam Project (DataScientest) — Implementation Diary

---

## 1. Repo setup (folder structure + naming)

### 1.1 Target folder structure 

We create the following initial structure in our repo root, keeping anything api-related together to have a clean build context fro Docker:  

```text
.
├── api
│   ├── Dockerfile
│   ├── main.py
│   └── requirements.txt
├── doc
│   └── IMPLEMENTATION.md
├── my-deployment-eval.yml
├── my-ingress-eval.yml 
├── my-secret-eval.yml
├──  my-service-eval.yml
└── README.md
```

---

## 2. Implementation roadmap

1) **Repo baseline**
   - Create the repo structure (`api/` + root YAML files)
   - Align Dockerfile paths so `./api` is the build context

2) **Local container proof (API starts)**
   - Build the FastAPI image locally (`docker build ... ./api`)
   - Run it locally (`docker run -p 8000:8000 ...`)
   - Prove it responds (`curl http://localhost:8000/status` → `1`)

3) **Capture image evidence (exam-defendable)**
   - Record: `docker images`, `docker inspect`, `docker history`
   - Add these commands + key outputs to `docs/IMPLEMENTATION.md`

4) **Kubernetes readiness: fix API DB wiring**
   - Update `api/main.py` so it:
     - connects to MySQL in the same Pod (`127.0.0.1` / `localhost`)
     - reads DB password from an env var (fed later via Kubernetes Secret)

5) **Local re-proof after code change**
   - Rebuild + rerun locally
   - Re-test `/status` (still `1`)

6) **Publish image for Kubernetes**
   - Push the verified image to Docker Hub (`docker push ...`)

7) **Kubernetes manifests (dependency order)**
   - Create `my-secret-eval.yml` (DB password `datascientest1234`)
   - Create `my-deployment-eval.yml`:
     - `replicas: 3`
     - Pod contains **two containers**: MySQL + FastAPI
     - FastAPI env var comes from the Secret
     - add minimal readiness/liveness probes for the API
   - Create `my-service-eval.yml` (ClusterIP exposing API on port 8000)
   - Create `my-ingress-eval.yml` (HTTP routing to the Service)

8) **Apply + verify in cluster**
   - Apply in order: Secret → Deployment → Service → Ingress
   - Verify rollout + endpoints:
     - `/status`
     - `/users`
     - `/users/{id}`
   - Capture proof commands + outputs in `docs/IMPLEMENTATION.md` for submission

---

## 3. Build Local Docker API image

### 3.1 Create Dockerfile & ensure it matches the `api/` build context

```dockerfile
# Base OS image (Ubuntu 20.04) for the container filesystem
FROM ubuntu:20.04

# Copy dependency list + code from the build context (api/) into the image
ADD requirements.txt main.py ./

# Refresh package index, install pip + MySQL client build deps for mysqlclient,
# install Python dependencies listed in requirements.txt
RUN apt update && apt install python3-pip libmysqlclient-dev -y && pip install -r requirements.txt

# Document that the service listens on port 8000 (does not publish it by itself)
# (port 8000 is a common default for FastAPI/uvicorn examples)
EXPOSE 8000

# Default startup: run FastAPI via uvicorn on all interfaces, port 8000
CMD uvicorn main:server --host 0.0.0.0 --port 8000
```

---

### 3.2 Build the image locally

Now we run `docker build` to create a **local** Docker image of our API. The command takes:

- a **tag/name** (`-t`) in the form `<namespace>/<image-name>:<tag>`  
  - `<namespace>` = Docker Hub username (or org)  
  - `<image-name>` = freely chosen image/repo name  
  - `<tag>` = version label (e.g. `1.0.0`)
- a **build context path** (`<build-context-path>`)  
  - this is the folder Docker sends to the build engine  
  - **only files inside this folder** are available to `ADD`/`COPY`

**Note:** `docker build` creates the image **locally only**. Docker Hub is needed later so Kubernetes can pull the image.

Here’s the schema:

~~~bash
# Build a local Docker image (this does **not** upload anything to Docker Hub)
# -t = assigns a local image reference ("tag") to the result
# <namespace> = Docker Hub username / org
# <image-name>:<tag> = image name + version tag (e.g. 1.0.0)
# <build-context-path> = folder sent to Docker (only files inside are available to ADD/COPY)
docker build -t <namespace>/<image-name>:<tag> <build-context-path>

# Example:
docker build -t <dockerhub-username>/user-api:1.0.0 ./api
~~~

To build a local Docker image from our `api/` folder, run this **from the repo root**:

~~~bash
docker build -t mayinx/fastapi-mysql-k8s:1.0.0 ./api
~~~

**Important:** This image reference (schema `<dockerhub-username>/<image-name>:<tag>`, here `mayinx/fastapi-mysql-k8s:1.0.0`) will be reused consistently:
- for `docker build` (local build)
- for `docker push` (upload to Docker Hub)
- in Kubernetes under `Deployment.spec.template.spec.containers[].image`

---

## 4. Local verification (proof the image exists + runs + the api is available)

### 4.1 Confirm the image exists locally
List images filtered by repository name:

```bash
docker images "mayinx/fastapi-mysql-k8s"
```

We should see:

```bash
IMAGE                            ID             DISK USAGE   CONTENT SIZE
mayinx/fastapi-mysql-k8s:1.0.0   e4811b1e6bcb        774MB          202MB
```

---

### 4.2 Optional: Inspect image metadata (deep inspection)
```bash
docker inspect mayinx/fastapi-mysql-k8s:1.0.0
```

Should give us (among others):
- `Config` > `ExposedPorts` should include "8000/tcp"
- `Config` > `Cmd` = `uvicorn main:server --host 0.0.0.0 --port 8000`

---

### 4.3 Run the container locally (foreground)
```bash
# Run the FastAPI image locally and expose it at http://localhost:8000 
# (foreground, logs visible).
# '--rm'         =  Remove the container automatically when it stops 
#                   (the image remains).
# '-p 8000:8000' =  Port mapping: Maps host port 8000 to container port 8000 
#                   (curl localhost:8000 hits the app inside).
# 'mayinx...'    =  Image reference to run.
docker run --rm -p 8000:8000 mayinx/fastapi-mysql-k8s:1.0.0
```

Expected logs include a line like “`Uvicorn running on ...:8000`”:

```bash
...$ docker run --rm -p 8000:8000 mayinx/fastapi-mysql-k8s:1.0.0
INFO:     Started server process [7]
INFO:     Waiting for application startup.
INFO:     Application startup complete.
INFO:     Uvicorn running on http://0.0.0.0:8000 (Press CTRL+C to quit)
INFO:     172.17.0.1:60070 - "GET /status HTTP/1.1" 200 OK
INFO:     172.17.0.1:60070 - "GET /favicon.ico HTTP/1.1" 404 Not Found
```

---

### 4.5 Check api-endpoints `/status` + `/docs` 

#### New terminal: curl proof against `/status`
While the container is still running, open a second terminal:

```bash
curl -s http://localhost:8000/status; echo
# => "1"
```

If we receive "1", we have proof that our container is running and the FastAPI server inside it is responding successfully on port 8000.


#### Check `/status` + `/docs`in browser 

- http://localhost:8000/status  => should render "1"
- http://localhost:8000/docs    => should open the User API Docs / Swagger UI 

---

## 5. Local integration test (API ↔ MySQL) with 2 Docker Compose services (before Kubernetes)

- The `/status` endpoint works locally, but `/users` fails, since it requires a running MySQL database.
- Before we introduce Kubernetes manifests, we use Docker Compose to perform a short local integration test to prove that:
  - the API can connect to MySQL
  - credentials are correct
  - the expected database/table exists (`Main.Users`)

- Goal: Limit the later Kubernetes debugging (hopefully) to “manifests and wiring” - instead of “manifests + broken app”.

---

### 5.1 Make DB connection settings environment-driven (K8s-friendly)

#### Settings requirements
- **Kubernetes**: In Kubernetes, MySQL and the API will run in the same Pod, so the API will reach MySQL via `127.0.0.1:3306`.  
  - `3306` is the default TCP port for MySQL. Unless explicitly reconfigured, MySQL listens on port `3306` inside the container.
  
- **Docker Compose**: In Docker Compose, MySQL and the API will be implemented as separate services (`api` + `db`) that run in separate containers, so the API will reach MySQL via the Compose service name `db:3306`.

#### Create a shared `.env`-file (local only)

To support both setups (Compose now, Kubernetes later), we keep connection settings in environment variables stored in a local `.env` file. 

Example with redacted secrets:


```bash
# .env — shared env for local API↔DB integration test (LOCAL ONLY; do not commit)
MYSQL_HOST=db
MYSQL_PORT=3306
MYSQL_USER=<set-locally>
MYSQL_PASSWORD=<set-locally>
MYSQL_DATABASE=Main
```

> **Important:** Do NOT commit `.env` (with real local values). Add `.env` to `.gitignore`.

Reasoning: Keeping local configuration in an `.env` file allows us to: 
- Run the same app locally (Compose) and later in Kubernetes (via env vars / Secrets),
- Avoid hardcoding credentials in code,
- Avoid committing secrets to git.


**Import config in `api/main.py`:**  
We use the `os`-lib to import the env-vars:

~~~python
import os

# creating a connection to the database
mysql_host = os.getenv("MYSQL_HOST", "127.0.0.1")
mysql_port = os.getenv("MYSQL_PORT", "3306")
mysql_url = f"{mysql_host}:{mysql_port}"

mysql_user = os.getenv("MYSQL_USER", "") # provided via Secret / env only
mysql_password = os.getenv("MYSQL_PASSWORD", "") # provided via Secret / env only
database_name = os.getenv("MYSQL_DATABASE", "Main")
~~~


---

### 5.2 Create a temporary Docker Compose file (2 services)

Create `compose.yml` in the repo root, which functions as temporarty helper for local proof:

~~~yaml
# compose.yaml 

# Utilized for local integration test (API ↔ MySQL) before Kubernetes implementation
# Purpose: prove DB connectivity + env-var wiring locally, so Kubernetes 
# debugging later stays focused on manifests.

services:
  # ---------------------------------------------------------------------------
  # db — MySQL database (exsiting image) | provides Main.Users for the API
  # ---------------------------------------------------------------------------
  db:
    # Use the predefined MySQL image 
    image: datascientest/mysql-k8s:1.0.0

    environment:
      # MySQL INIT expects MYSQL_ROOT_PASSWORD; we map it from our shared MYSQL_PASSWORD
      MYSQL_ROOT_PASSWORD: ${MYSQL_PASSWORD}

     # Optional: expose DB to the host for debugging (the API can reach db:3306 without this)
    ports:
      - "3306:3306"

  # ---------------------------------------------------------------------------
  # api — FastAPI service (builds locally) | connects to db via db:3306
  # ---------------------------------------------------------------------------
  api:
    # Build the API image from ./api (Dockerfile + main.py + requirements.txt)
    build:
      context: ./api

    # Tag the built image USING THE same reference we’ll later push + use in Kubernetes  
    image: mayinx/fastapi-mysql-k8s:1.0.0

    # Load shared local env vars (NOT committed; real values live in .env)
    # (e.g. MYSQL_HOST=db, MYSQL_PORT=3306, credentials)
    env_file:
      - .env

    # Expose API to the host so we can test via curl/browser at localhost:8000
    ports:
      - "8000:8000"

    # Start db first (note: this does not guarantee db is "ready", only started)  
    depends_on: 
    - db
~~~

**Notes:**
- MySQL runs as container `db` on `3306` (the default TCP port for MySQL).
- The API container can reach it by DNS name `db` inside the Compose network. 
- The FastAPI server is served by uvicorn and is configured to listen on container port `8000` (see Dockerfile: `EXPOSE 8000` + `uvicorn ... --port 8000`); port 8000 is a common default for FastAPI/uvicorn examples.
- In Compose, `ports: - "8000:8000"` maps "host port 8000" to "container port 8000", so we can call `http://localhost:8000/status|users` 
- We inject the config vars (incl. password) via env var to mimic the later Kubernetes Secret approach and keep secrets out of the `main.py` right from the start  

---

### 5.3 Run the local integration test

Start both services (build API image as needed):

~~~bash
docker compose -p k8s up --build
~~~

Open a browser and/or a second terminal and test the api-endpoints:

~~~bash
curl -s http://localhost:8000/status; echo
# => 1

curl -s http://localhost:8000/users | jq
# => [
#      {
#        "user_id": 1,
#        "username": "August",
#        "email": "..."
#      },
#      {
#       "user_id": 2,
#       "username": "Linda",
#       "email": "eleifend.Cras.sed@cursusnonegestas.com"
#      },
#      ...
#    ]

curl -s http://localhost:8000/users/1 | jq
# => {
#      "user_id": 1,
#      "username": "August",
#      "email": "..."
#    }
~~~

**Notes**
- If `/users` fails immediately after startup, MySQL may not be ready yet. Wait ~10–30 seconds and retry.
- `/users` should return a JSON list of users if the DB is initialized as expected by the provided MySQL image.

Stop and clean up:

~~~bash
docker compose down
~~~

---


### 5.4 Fix `/users` and `/users/{id}` im `main.py` (SQLAlchemy 2.0 + FastAPI path syntax)

Due to some issues with the provided `main.py`, only accessing the `/status`-endpoint works as expected, but `/users` and `users/{id}` return **500** with:

- `sqlalchemy.exc.ObjectNotExecutableError: Not an executable object: 'SELECT * FROM Users;'`

**Cause (SQLAlchemy 2.0):** The original lesson code uses 

```python
connection.execute("SELECT ...") 
```
with a plain SQL string. In SQLAlchemy 2.0, plain strings are no longer executable statements.

**Fix (minimal):** Replace `connection.execute("...")` with `connection.exec_driver_sql("...")` for raw SQL strings:

```python
connection.exec_driver_sql("SELECT ...") 
```

Additionally, the lesson uses an invalid FastAPI route pattern:

```python
# 'user_id:int' is not supported in FastAPI path strings
@server.get('/users/{user_id:int}', response_model=User) 
async def get_user(user_id):
  # ...
```

**Fix:** Use `'/users/{user_id}'` and type the parameter in the function signature (`user_id: int`):


```python
@server.get('/users/{user_id}', response_model=User)
async def get_user(user_id: int):
```

> Implementation reference: see the **NOTE** blocks in `api/main.py` above the `/users` and `/users/{user_id}` endpoints (documenting the exact change and why it was needed).



