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