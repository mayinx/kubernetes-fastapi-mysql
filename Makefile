DOCKER_IMAGE_REF := mayinx/fastapi-mysql-k8s:1.0.0
BUILD_CONTEXT_PATH := ./api

COMPOSE_PROJECT := k8s

docker-build:
	echo "# [make docker-build] Build docker image locally: ${DOCKER_IMAGE_REF} (context: ${BUILD_CONTEXT_PATH})"
	docker build -t ${DOCKER_IMAGE_REF} ${BUILD_CONTEXT_PATH} 

docker-run:
	echo "# [make docker-run] Run docker container locally (foreground)"
	docker run --rm -p 8000:8000 ${DOCKER_IMAGE_REF}

compose-build:
	echo "# [make compose-build] Start stack and rebuild images if Dockerfiles changed" 
	docker compose -p $(COMPOSE_PROJECT) up --build

compose-down:
	echo "# [make compose-down] Stop stack + remove containers/networks"
	docker compose -p $(COMPOSE_PROJECT) down

