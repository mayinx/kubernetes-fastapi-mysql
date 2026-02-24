

# Implementation Steps / Log

> ## 👤 About
> This README contains my personal implementation log (“exam build diary”).  
> It was written while building the solution to keep milestones, decisions, and commands reproducible.  
> For the TL;DR command checklist and quick setup guide, see: **[docs/RUNBOOK.md](RUNBOOK.md)**.

---

## 📌 Index (top-level)

1. [Project scaffold (folder structure + naming)](#1--project-scaffold-folder-structure--naming)
2. [Implementation roadmap](#2-implementation-roadmap)
3. [Build Local Docker API image](#3-build-local-docker-api-image)
4. [Local verification](#4-local-verification-proof-the-image-exists--runs--the-api-is-available)
5. [Local integration test (Docker Compose)](#5-local-integration-test-api--mysql-with-2-docker-compose-services-before-kubernetes)
6. [Publish the API image to Docker Hub](#6-publish-the-api-image-to-docker-hub-so-kubernetes-can-pull-it)
7. [Kubernetes manifests (YAML files)](#7-kubernetes-manifests---create-the-required-yaml-files)
8. [Apply + verify end-to-end](#8-apply-manifests-and-verify-end-to-end-secret--deployment--service--ingress)
---

## 1.  Project scaffold (folder structure + naming)

### 1.1 Target folder structure 

We create the following initial structure in our repo root, keeping anything api-related together to have a clean build context for Docker:  

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
├── my-service-eval.yml
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
   - Create `my-secret-eval.yml` (DB password <set-locally>)
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
# .env.example — shared env for local API↔DB integration test (LOCAL ONLY; do not commit)
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

#### Start both services (build API image as needed):

~~~bash
docker compose -p k8s up --build
~~~

#### Open a browser and/or a second terminal and test the api-endpoints:

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
- `/users` should return a JSON list of users and `users/:id` a single user if the DB is initialized as expected by the provided MySQL image. 
- I the db-related api-endpoints fail with a 500, check the fix in the following chapter first (see. 5.4)
-  

#### Stop and clean up:

~~~bash
docker compose -p k8s down
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


## 6. Publish the API image to Docker Hub (so Kubernetes can pull it)

Since the local integration test work (`/status`, `/users`, `/users/{id}`), we can now publish the API image to Docker Hub. Kubernetes nodes will later pull this image using the same image reference we tag locally.

---

### 6.1 Verify the image reference (local)

~~~bash
docker images "mayinx/fastapi-mysql-k8s"
# expect: mayinx/fastapi-mysql-k8s:1.0.0
~~~

---

### 6.2 Login to Docker Hub (one-time per machine/session)

~~~bash
docker login
~~~

If login succeeds, Docker stores a credential token locally so you can push.

---

### 6.3 Push the image

~~~bash
docker push mayinx/fastapi-mysql-k8s:1.0.0
~~~

Expected: Docker uploads layers (only what’s missing on Docker Hub).

---

### 6.4 Optional sanity check: pull from Docker Hub (proves it’s published)

~~~bash
docker pull mayinx/fastapi-mysql-k8s:1.0.0
~~~

If this succeeds, we have proof that:
- the image exists remotely on Docker Hub
- Kubernetes will be able to pull it later using the same reference

---

## 7. Kubernetes manifests - create the required YAML files 

Now that the API image is available on Docker Hub, we can start creating the required Kubernetes manifest files:

- `my-secret-eval.yml`
- `my-deployment-eval.yml`
- `my-service-eval.yml`
- `my-ingress-eval.yml`

We build these in dependency order so each resource can reference what it needs.

> The full contents of the YAML fiels are not all duplicated here - see the corresponding yaml-files themselves for details, which are commented sufficiently. The following focusses on the description of the purpose and wiring of teh various k8s components. 

---

### 7.1 Create the Secret (`my-secret-eval.yml`) — credentials

First we create a **Secret** named **`mysql-secret`** that stores the DB password (`MYSQL_PASSWORD`) so the API can read it from env vars and the password is not hardcoded in `api/main.py`.

**Goal:** store the DB password as a Kubernetes Secret so it is **not hardcoded** in `api/main.py`.

> #### Secret (The Vault / The Configuration)  
> A **Kubernetes Secret** acts a vault - it is an object designed to store and manage sensitive information — such as passwords, OAuth tokens, and SSH keys—separately from the app code. When a Secret is created, Kubernetes stores it in `etcd` (the cluster's database). From there, the Deployment "injects" the Secret with its sensitive data into the Pod(s) as they start up.  

**Wiring (how it connects to other components):**
- Referenced by `my-deployment-eval.yml` via `secretKeyRef` for:
  - **db container**: sets `MYSQL_ROOT_PASSWORD` (MySQL initialization)
  - **api container**: sets `MYSQL_PASSWORD` (API connection)

**Key configs that must match:**
- `metadata.name` must match `secretKeyRef.name` in the Deployment.
- the Secret key (e.g. `MYSQL_PASSWORD`) matches what the API expects via environment variables - and must match `secretKeyRef.key` in the Deployment.
- We use `stringData` for readability; Kubernetes stores the final value base64-encoded under `data`.

~~~yaml
# my-secret-eval.example.yml
apiVersion: v1
kind: Secret
metadata:
  name: mysql-secret                # Secret name referenced by the Deployment
type: Opaque                        # Generic key/value secret
stringData:                         # Human-readable input; Kubernetes stores it base64-encoded in `data`
  MYSQL_PASSWORD: <set-locally> # DB password (must NOT be hardcoded in main.py)
~~~

---

### 7.2 Create the Deployment (`my-deployment-eval.yml`) — 3 Pods, 2 containers per Pod

Now that the Secret is in place, we create a Deployment named **`api-mysql`** with `replicas: 3`. Each Pod runs **two containers** (`db` + `api`), and both containers receive the password from `mysql-secret` (MySQL init + API connection).

**Goal:** one Kubernetes Deployment that creates the required workload:
- `replicas: 3` 
- each Pod contains 2 containers (teh so called "sidecar pattern" => two containers in one pod)
  - `db` container: `datascientest/mysql-k8s:1.0.0`
  - `api` container: `mayinx/fastapi-mysql-k8s:1.0.0` (pulled from Docker Hub)
    - The API container is injected with the required  DB password defined in the Secret (injected on API-Pod start).

> #### Deployment (The Manager / The Logic)
> A **Kubernetes Deployment** is a high-level object that manages the lifecycle of Pods based on a **Pod Template** (blueprint).  
> Instead of creating Pods directly, a Deployment object is created that ensures the desired number of Pods are running and healthy at all times.
>

> #### Deployment Key Features
> A Deployment provides several automated features that make managing containers much easier:  
> - **Self-healing:** if a Pod dies, the Deployment replaces it.
> - **Scaling:** manages replicas via a **ReplicaSet**.
> - **Rollouts / rollbacks:** performs rolling updates (and can revert).
> - **Pause / resume:** rollout can be paused for verification.

> #### Relation between **Deployment <-> ReplicaSet <-> Pods** 
> To be precise, a Deployment doesn't manage Pods directly; it manages a **ReplicaSet**, which in turn manages the Pods. 
> - **Deployment** defines desired state + update strategy (e.g. which image to run).
> - **ReplicaSet** ensures the exact number of Pod replicas are running 
> - **Pods** is the actual running instance of the application.
 
**Wiring (how it connects to other components):**
- Uses `my-secret-eval.yml` for password injection into both containers.
- Is selected by `my-service-eval.yml` via Pod labels (Service selector → Deployment template labels).
- Is exposed externally via `my-ingress-eval.yml` → Service → Pods.

**Key configs that must match:**
- `spec.replicas` must be **3** (requirement).
- `spec.selector.matchLabels` must exactly match `spec.template.metadata.labels`.
- The Pod label (e.g. `app: api-mysql`) must match the Service selector.
- `api` container `image:` must be the pushed Docker Hub reference.
- API DB wiring must reflect **same-Pod networking** (both containers run in the same Pod, so the API connects to MySQL via `127.0.0.1:3306`)
  - `MYSQL_HOST=127.0.0.1`
  - `MYSQL_PORT=3306`
- `secretKeyRef` name/key must match `my-secret-eval.yml`.
- Secret mapping must be consistent: 
  - `MYSQL_ROOT_PASSWORD` for the MySQL container initialization
  - `MYSQL_PASSWORD` for the API connection
- Probes use `/status` as a simple health signal (readiness + liveness).

~~~yaml
# my-deployment-eval.yml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-mysql                 # Deployment name
spec:
  replicas: 3                     # Required: 3 Pods (each Pod contains BOTH containers)
  selector:
    matchLabels:
      app: api-mysql              # Deployment manages Pods with this label
  template:
    metadata:
      labels:
        app: api-mysql            # Pod label (also used by the Service selector)
    spec:
      containers:
        - name: db
          image: datascientest/mysql-k8s:1.0.0   # MySQL container image (provided by the exercise)
          env:
            # MySQL init expects MYSQL_ROOT_PASSWORD (we source it from the Secret)
            - name: MYSQL_ROOT_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: mysql-secret
                  key: MYSQL_PASSWORD
          ports:
            - containerPort: 3306                # MySQL listens on 3306 inside the Pod

        - name: api
          image: mayinx/fastapi-mysql-k8s:1.0.0  # Our pushed FastAPI image (pulled from Docker Hub)
          env:
            # Same-Pod networking: the API reaches MySQL via localhost (127.0.0.1) on port 3306
            - name: MYSQL_HOST
              value: "127.0.0.1"
            - name: MYSQL_PORT
              value: "3306"
            - name: MYSQL_USER
              value: "root"
            # API reads password from env (Secret), not from code
            - name: MYSQL_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: mysql-secret
                  key: MYSQL_PASSWORD
            - name: MYSQL_DATABASE
              value: "Main"
          ports:
            - containerPort: 8000                # FastAPI/uvicorn listens on 8000 inside the Pod
          readinessProbe:
            # Ready = endpoint responds -> traffic can be routed to this Pod
            httpGet:
              path: /status
              port: 8000
            initialDelaySeconds: 5
            periodSeconds: 5
          livenessProbe:
            # Live = endpoint responds -> if it fails, K8s restarts the container
            httpGet:
              path: /status
              port: 8000
            initialDelaySeconds: 10
            periodSeconds: 10
~~~

---

### 7.3 Create the Service (`my-service-eval.yml`)

Since Pods are ephemeral by nature, we need to create a ClusterIP Service (named **`api-svc`**) that provides a stable in-cluster IP, selects the **`api-mysql`** Pods via labels, and exposes the API on port `8000` inside the cluster (load-balanced across replicas).

**Goal:** expose the API within the cluster on port 8000 and load-balance across the 3 API Pods.

> #### Service (The Dispatcher / The Stable Internal IP)
> A Kubernetes **Service** (here: `ClusterIP`) manages the networking of Pods. The Service provides a single, stable in-cluster endpoint (DNS name + virtual IP address) for a set of Pods. It provides a stable in-cluster address and load-balancing across Pods.  
> Since Pods are "ephemeral" (IPs change as Pods restart/roll), we can't rely on a Pod's IP to connect to it. Instead, the Service selects Pods via labels and forwards traffic to healthy endpoints, effectively load-balancing across replicas. 
> In our setup, the Ingress routes to the **Service**, and the Service routes to the **Pods** managed by the Deployment.

**Wiring (how it connects to other components):**
- Selects the Pods created by `my-deployment-eval.yml` (via matching labels).
- Is used as the backend target in `my-ingress-eval.yml`.

**Key configs that must match:**
- `spec.selector` must match the Pod label from the Deployment template (otherwise the Service has 0 endpoints).
- `targetPort: 8000` must match the API container port (uvicorn listens on `8000`).
- `metadata.name` must match the Ingress backend service name (`backend.service.name`)..

~~~yaml
# my-service-eval.yml
apiVersion: v1
kind: Service
metadata:
  name: api-svc                   # Stable in-cluster address for the API Pods
spec:
  selector:
    app: api-mysql                # Select Pods created by the Deployment
  ports:
    - name: http
      port: 8000                  # Service port (clients hit this)
      targetPort: 8000            # Pod container port (forwarded to api container)
  type: ClusterIP                 # Internal-only Service (Ingress will expose it externally)
~~~

---

### 7.4 Create the Ingress (`my-ingress-eval.yml`)

Finally, to allow external access, we create an Ingress named **`api-ingress`** that routes external HTTP requests (path `/`) to the **`api-svc`** Service on port `8000` (via the cluster’s Ingress Controller).

**Goal:** expose the API externally via HTTP routing.

> #### Ingress (The Gatekeeper / The Entrance)
> A Kubernetes **Ingress** is an object that manages external access to the Services in a cluster.
> I provides the HTTP entry point for traffic coming from outside the cluster and routes external requests (by host and/or path) to the corresponding Service inside the cluster. So Ingress routes to Services, and Services forward to the Pods behind them.  
> Ingress requires an Ingress Controller to be installed in the cluster (e.g. Traefik, NGINX Ingress).

**How it wires to other components:**
- Routes requests to the Service from `my-service-eval.yml` (`api-svc`) on port  `8000`.

**Key configs that must match / may need adjustment:**
- `ingressClassName` must match the Ingress Controller available in the cluster (often `nginx`, or `traefik` (very common on k3s)) - that means: **Before setting `ingressClassName`, ALWAYS check which IngressClass exists on the cluster** using `kubectl get ingressclass`:
  ~~~bash
  kubectl get ingressclass
  NAME      CONTROLLER                      PARAMETERS   AGE
  traefik   traefik.io/ingress-controller   <none>       10d
  ~~~
  - **Then set `spec.ingressClassName` accordingly** ( 
  - **If `ingressClassName` does not match, the Ingress may exist but routing will fail (often `404`).**

- `backend.service.name` must match `my-service-eval.yml`’s Service name (`api-svc`).
- `backend.service.port.number` must match the Service port (`8000`).

~~~yaml
# my-ingress-eval.yml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: api-ingress               # Ingress resource name
spec:
  ingressClassName: traefik       # Ingress controller to use ('nginx', 'traefik' etc. - adjust accordingly)
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: api-svc     # Route HTTP traffic to the Service
                port:
                  number: 8000
~~~

---

## 8. Apply manifests and verify end-to-end (Secret → Deployment → Service → Ingress)

Now the Kubernetes resources can be applied in dependency order to verify:
- 3 replicas are running
- the API is reachable through the Ingress
- `/status`, `/users`, `/users/{id}` work as expected

Applying the Kubernetes resources in dependency order is necessary, so each object exists before something else references it.  

---

### 8.1 Apply the manifests (dependency order)

To apply the Kubernetes resources, we use `kubectl apply`. It creates or updates the objects defined in a YAML file and reconciles them with the cluster (“apply this desired state”) - schema

~~~bash
$ kubectl apply -f <file> 
~~~ 

~~~bash
# Apply Secret first (the Deployment references it via secretKeyRef for DB init + API password)
$ kubectl apply -f my-secret-eval.yml
secret/mysql-secret created

# Apply Deployment next (creates the Pods; Pods need the Secret at startup to set env vars)
$ kubectl apply -f my-deployment-eval.yml
deployment.apps/api-mysql created

# Apply Service next (selects the Pods via labels and provides a stable in-cluster endpoint + load-balancing)
$ kubectl apply -f my-service-eval.yml
service/api-svc created

# Apply Ingress last (routes external HTTP traffic to the Service; Ingress backend depends on the Service name/port)
$ kubectl apply -f my-ingress-eval.yml
ingress.networking.k8s.io/api-ingress configured
~~~

---

### 8.2 Watch rollout and check Pods/replicas

To verify that the Deployment successfully created the desired number of Pods and that both containers per Pod are ready we run `kubectl rollout status` + `kubectl get pods`:   

- `kubectl rollout status` waits for the Deployment rollout to complete; 
- `kubectl get pods` shows current Pod states.

~~~bash
# Wait until the Deployment rollout is complete
# rollout status = watches progress until the desired state is reached (or times out)
$ kubectl rollout status deployment/api-mysql
deployment "api-mysql" successfully rolled out

# List Pods for this Deployment by label
# -l ... = label selector (only Pods with app=api-mysql)
# -o wide = include node/IP details (useful for debugging)
$ kubectl get pods -l app=api-mysql -o wide
NAME                       READY   STATUS    RESTARTS   AGE   IP            NODE                      
api-mysql-5655b5fb-6kqxv   2/2     Running   0          17m   10.42.0.130   <NODE>
api-mysql-5655b5fb-7cspz   2/2     Running   0          17m   10.42.0.131   <NODE>
api-mysql-5655b5fb-ppmkd   2/2     Running   0          17m   10.42.0.129   <NODE>
~~~

Expected:
- 3 Pods in `Running`
- Ready `2/2` (sidecar - each Pod has 2 containers: `db` + `api`)

---

### 8.3 Check Service and endpoints

To confirm that the Service selects the Pods correctly and has live endpoints, we use `kubectl get svc` + `kubectl get endpoints`. 

Hint: If the Service selector is wrong, `Endpoints` will be empty and Ingress routing will fail. 

~~~bash
# Show the Service (ClusterIP + exposed port)
$ kubectl get svc api-svc
NAME      TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
api-svc   ClusterIP   10.43.220.117   <none>        8000/TCP   27m

# Show the resolved backend endpoints behind the Service (should point to the Pods)
$ kubectl get endpoints api-svc
NAME      ENDPOINTS                                            AGE
api-svc   10.42.0.129:8000,10.42.0.130:8000,10.42.0.131:8000   29m

~~~

Expected:
- `api-svc` exists and has endpoints on `:8000`
- endpoints list shows 3 addresses (one per Pod) on port `8000`

---

### 8.4 Check Ingress and get the access URL/IP

To inspect the Ingress status and to learn how to reach it (IP/hostname depends on the cluster + Ingress Controller) we use `kubectl get ingress`.  

Hint: If `ADDRESS` stays empty, the controller may not be installed or not exposing an external address.
and be sure that `CLASS` (== the ingressclassname) is identical with the result of `kubectl get ingressclass`. If those differ, your setup won't work.  

~~~bash
# Show Ingress rules + the assigned ADDRESS/HOSTS (if provided by the cluster)
$ kubectl get ingress api-ingress
NAME          CLASS     HOSTS   ADDRESS          PORTS   AGE
api-ingress   traefik   *       192.168.178.57   80      6d8h
~~~

---

### 8.5 Verify API endpoints via Ingress

We test the API through the Ingress entry point to confirm the full chain works: 

**Ingress → Service → Pods**  

~~~bash
# Replace <INGRESS_IP> with the Ingress ADDRESS from `kubectl get ingress`
$ curl -i http://<INGRESS_IP>/status; echo
#=> HTTP/1.1 200 OK
#   Content-Length: 1
#   Content-Type: application/json
#   Date: Mon, 23 Feb 2026 19:28:40 GMT
#   Server: uvicorn
#
#   1

# Pretty-print JSON list of users
$ curl -s http://<INGRESS_IP>/users | jq
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

# Pretty-print one user (id=1)
$ curl -s http://<INGRESS_IP>/users/1 | jq
# => {
#      "user_id": 1,
#      "username": "August",
#      "email": "..."
#    }
~~~

---

### 8.7 Capture evidence 

Implement a bash-script to create evicence - f.i.: 

- `kubectl get pods -l app=api-mysql -o wide`
- `kubectl get endpoints api-svc`
- `kubectl get ingress api-ingress`
- successful `curl` responses for `/status`, `/users`, `/users/1`

See `scripts/capture-proof.sh` + `evidence/` for details ...  

To run teh script:
~~~bash
./scripts/capture-proof.sh
~~~

Fallback (after port-forward) with a provided `BASE_URL`-env var:
~~~bash
BASE_URL=http://localhost:8000 ./scripts/capture-proof.sh
~~~

Output:
~~~text
evidence/<timestamp>/
  00_meta.txt
  01_pods.txt
  02_service.txt
  03_endpointslice.txt
  04_ingress.txt
  05_curl_status.txt
  06_curl_users.json
  07_curl_user_1.json
~~~
