

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

## 4. Local verification (proof the image exists + runs)

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

### 4.2 Inspect image metadata (deep inspection)
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

Expected logs include a line like “Uvicorn running on ...:8000”:

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

### 4.5 New terminal: curl proof against `/status`
While the container is still running, open a second terminal:

```bash
curl -s http://localhost:8000/status; echo
# => "1"
```

If we receive "1", we have proof that our container is running and the FastAPI server inside it is responding successfully on port 8000.

---


