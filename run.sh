#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

sudo apt-get install expect -y

# Clone the repository and checkout the specified branch
git config --global http.postBuffer 524288000
git clone --depth 1 --branch x1 https://github.com/FairCrypto/go-x1
cd go-x1

# Create Dockerfile
cat > docker/Dockerfile <<'EOF'
FROM golang:1.18-alpine as builder

RUN apk add --no-cache make gcc musl-dev linux-headers git

WORKDIR /go/go-x1
COPY . .

ARG GOPROXY
RUN go mod tidy
RUN go mod download
RUN make x1

FROM alpine:latest

RUN apk add --no-cache ca-certificates

# Create and set /app as the working directory
WORKDIR /app
COPY --from=builder /go/go-x1/build/x1 /app/

EXPOSE 5050 18545 18546

ENTRYPOINT ["/app/x1"]
EOF

# Create Docker Compose file
cat > docker-compose.yml <<'EOF'
version: '3.8'

services:
  x1:
    build:
      context: .
      dockerfile: docker/Dockerfile
    command: ["--testnet", "--syncmode", "snap", "--datadir", "/app/.x1"]
    volumes:
      - ./xen:/app/.x1  # Mount the 'xen' volume to /app/.x1 inside the container
    ports:
      - "5050:5050"   # Expose the necessary ports
      - "18545:18545"
      - "18546:18546"
    container_name: x1

volumes:
  xen:  # Define the 'xen' volume for persistence
EOF

# Build the Docker image
docker compose build

# Create the persistent directory and start the container
mkdir -p xen && docker compose up -d


# Prompt for the password and store it in a temporary file
echo "Please enter the password for the new account:"
read -s ACCOUNT_PASSWORD
echo $ACCOUNT_PASSWORD > ./account_password.txt

echo "Please enter the password for the new validator:"
read -s VALIDATOR_PASSWORD
echo $VALIDATOR_PASSWORD > ./validator_password.txt

# Use the password file for the docker exec command
docker exec -i x1 /app/x1 account new --datadir /app/.x1 --password ./account_password.txt
docker exec -i x1 /app/x1 validator new --datadir /app/.x1 --password ./validator_password.txt

# Clean up: remove the temporary password files
rm ./account_password.txt
rm ./validator_password.txt
