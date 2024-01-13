#!/bin/bash -x

# Exit immediately if a command exits with a non-zero status.
set -e

# Check if Docker is already installed
if command -v docker > /dev/null 2>&1; then
echo "Docker is already installed."
else
# Docker is not installed, proceed with installation
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
rm $HOME/get-docker.sh
sudo apt-get update -y
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y

fi

# Add the current user to the Docker group if not already added
if ! groups ${USER} | grep -q '\bdocker\b'; then
    sudo groupadd docker
    sudo usermod -aG docker ${USER}
    echo "User added to docker group. Please log out and log back in for this to take effect."
else
    echo "User already in docker group."
fi


# Display Docker version
docker -v

sleep 1

# Clone the repository and checkout the specified branch
git config --global http.postBuffer 524288000
git clone --depth 1 --branch x1 https://github.com/FairCrypto/go-x1 || echo "folder is existing"
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



mkdir -p xen
read -p ' ^|^m Enter account password: ' input_password

while [ "$input_password" == "" ]
do
  echo -e "\033[0;31m   ^|^x Incorrect password. \033[0m \n"
  read -p ' ^|^m Enter account password: ' input_password
done


# Output the password to a file
echo "$input_password" > ./xen/account_password.txt


read -p ' ^|^m Enter Validator password: ' input_validator_password

while [ "$input_validator_password" == "" ]
do
  echo -e "\033[0;31m   ^|^x Incorrect password. \033[0m \n"
  read -p ' ^|^m Enter Validator password: ' input_validator_password
done

# Output the password to a file
echo "$input_validator_password" > ./xen/validator_password.txt

chmod 775 ./xen/*.txt

# Create Docker Compose file
cat > docker-compose.yml <<'EOF'
version: '3.8'

services:
  x1:
    build:
      context: .
      dockerfile: docker/Dockerfile
    command: ["--testnet", "--syncmode", "snap", "--datadir", "/app/.x1", "--xenblocks-endpoint", "ws://xenblocks.io:6668", "--gcmode", "full"]
    volumes:
      - ./xen:/app/.x1  # Mount the 'xen' volume to /app/.x1 inside the container
      - ./xen/account_password.txt:/app/account_password.txt
      - ./xen/validator_password.txt:/app/validator_password.txt
    ports:
      - "5050:5050"   # Expose the necessary ports
      - "18545:18545"
      - "18546:18546"
    container_name: x1
    ulimits:
      nofile:
        soft: 500000
        hard: 500000

EOF


# Rest of your script...

# Build the Docker image
docker compose build

# Create the persistent directory and start the container
docker compose up -d

# Wait for the container to be fully up and running
sleep 3
echo "Waiting for the x1 container to initialize..."
counter=0
max_attempts=3  # Maximum number of attempts (30 attempts with 1-second delay each)

while [ "$(docker container inspect -f '{{.State.Running}}' x1)" != "true" ]; do
    if [ $counter -eq $max_attempts ]; then
        echo "x1 container is not running. Exiting script."
        exit 1
    fi
    sleep 1
    ((counter++))
done

echo "x1 container is now running."
# Use the password file for the docker exec command
docker exec -i x1 /app/x1 account new --datadir /app/.x1 --password /app/account_password.txt


docker exec -i x1 /app/x1 validator new --datadir /app/.x1 --password /app/validator_password.txt

