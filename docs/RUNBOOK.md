# 🧭 Runbook (TL;DR) 

> ## 👤 About
> This runbook is the **short, command-first** version of the project setup, excecution and verification flow.  
> It’s meant as a quick reference for reruns without the long-form diary.  
> For the full narrative log, see: **[docs/IMPLEMENTATION.md](IMPLEMENTATION.md)**.

---

## 📌 Index (top-level)
1. [Prerequisites](#0-prerequisites)
2. [Repo scaffold](#1-repo-scaffold-what-must-exist)
3. [Local build (API image)](#2-local-build-api-image)
4. [Local integration test (Compose)](#3-local-integration-test-api--mysql-with-docker-compose-recommended)
5. [Publish image to Docker Hub](#4-publish-api-image-to-docker-hub-required-for-kubernetes-pulls)
6. [Kubernetes manifests (pre-flight)](#5-kubernetes-manifests-pre-flight-checks)
7. [Apply manifests](#6-apply-manifests-dependency-order)
8. [Verify rollout + wiring](#7-verify-rollout--wiring)
9. [Call the API](#8-call-the-api-ingress-path)
10. [Capture evidence](#9-capture-evidence-proof-bundle)
11. [Troubleshooting](#10-troubleshooting-fast)

---

## 0) Prerequisites

- 🐳 Docker installed (build + push API image)
- ☸️ kubectl configured (`kubectl get nodes` works)
- 🌐 Ingress Controller installed in the cluster (e.g. Traefik on k3s)

Check access + available ingress classes:
~~~bash
kubectl get nodes
kubectl get ingressclass
~~~

---

## 1) Repo scaffold (what must exist)

Expected structure (high level):
~~~text
api/                  # Docker build context for API image
  Dockerfile
  main.py
  requirements.txt
my-secret-eval.yml
my-deployment-eval.yml
my-service-eval.yml
my-ingress-eval.yml
scripts/capture-proof.sh
~~~

---

## 2) Local build (API image)

Build the API image locally from the repo root:
~~~bash
docker build -t mayinx/fastapi-mysql-k8s:1.0.0 ./api
docker images "mayinx/fastapi-mysql-k8s"
~~~

(Optional) Smoke test (API starts):
~~~bash
docker run --rm -p 8000:8000 mayinx/fastapi-mysql-k8s:1.0.0
# new terminal:
curl -s http://localhost:8000/status; echo
~~~

---

## 3) Local integration test (API ↔ MySQL) with Docker Compose (recommended)

Purpose: validate DB wiring + credentials + schema (`Main.Users`) before Kubernetes.

### 3.1 Create `.env` (local only)
~~~bash
# LOCAL ONLY; do not commit
cat > .env <<'EOF'
MYSQL_HOST=db
MYSQL_PORT=3306
MYSQL_USER=root
MYSQL_PASSWORD=<set-locally>
MYSQL_DATABASE=Main
EOF
~~~

### 3.2 Start stack
~~~bash
docker compose -p k8s up --build
~~~

### 3.3 Verify endpoints locally
~~~bash
curl -s http://localhost:8000/status; echo
curl -s http://localhost:8000/users | jq
curl -s http://localhost:8000/users/1 | jq
~~~

### 3.4 Stop/cleanup
~~~bash
docker compose -p k8s down
~~~

---

## 4) Publish API image to Docker Hub (required for Kubernetes pulls)

~~~bash
docker login
docker push mayinx/fastapi-mysql-k8s:1.0.0
~~~

(Optional) sanity pull:
~~~bash
docker pull mayinx/fastapi-mysql-k8s:1.0.0
~~~

---

## 5) Kubernetes manifests (pre-flight checks)

### 5.1 Confirm Ingress class name on this cluster
Your Ingress must use an **existing** class (commonly `traefik` on k3s).

~~~bash
kubectl get ingressclass
~~~

Ensure `my-ingress-eval.yml` uses the correct value:
- `spec.ingressClassName: traefik` (or `nginx`, etc.)

---

## 6) Apply manifests (dependency order)

~~~bash
kubectl apply -f my-secret-eval.yml
kubectl apply -f my-deployment-eval.yml
kubectl apply -f my-service-eval.yml
kubectl apply -f my-ingress-eval.yml
~~~

---

## 7) Verify rollout + wiring

### 7.1 Deployment rollout + Pods
~~~bash
kubectl rollout status deployment/api-mysql
kubectl get pods -l app=api-mysql -o wide
~~~

Expected: 3 Pods, each `READY 2/2`.

### 7.2 Service + endpoints
~~~bash
kubectl get svc api-svc -o wide
kubectl get endpointslice -l kubernetes.io/service-name=api-svc -o wide
~~~

Expected: 3 endpoints on port 8000.

### 7.3 Ingress address
~~~bash
kubectl get ingress api-ingress -o wide
~~~

Note the `ADDRESS` column.

---

## 8) Call the API (Ingress path)

If Ingress has an address:
~~~bash
curl -i http://<INGRESS_ADDRESS>/status; echo
curl -s http://<INGRESS_ADDRESS>/users | jq
curl -s http://<INGRESS_ADDRESS>/users/1 | jq
~~~

Fallback (Ingress not reachable): port-forward Service
~~~bash
kubectl port-forward svc/api-svc 8000:8000
# new terminal:
curl -s http://localhost:8000/status; echo
curl -s http://localhost:8000/users | jq
curl -s http://localhost:8000/users/1 | jq
~~~

---

## 9) Capture evidence (proof bundle)

Run:
~~~bash
./scripts/capture-proof.sh
~~~

Fallback (after port-forward):
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

---

## 10) Troubleshooting (fast)

### Ingress returns 404
Most common cause: `ingressClassName` mismatch.

~~~bash
kubectl get ingressclass
kubectl get ingress api-ingress -o wide
kubectl apply -f my-ingress-eval.yml
~~~