.PHONY: build run dev test migrate seed docker

build:
	go build -o bin/gastrocore-server ./cmd/server

run: build
	./bin/gastrocore-server

dev:
	go run ./cmd/server

test:
	go test ./...

migrate-up:
	go run ./cmd/migrate up

migrate-down:
	go run ./cmd/migrate down

seed:
	go run ./cmd/seed

seed-force:
	go run ./cmd/seed --force

seed-wipe:
	go run ./cmd/seed --wipe

docker-build:
	docker build -t gastrocore-server .

docker-run:
	docker-compose up -d

lint:
	golangci-lint run ./...

generate:
	go generate ./...
