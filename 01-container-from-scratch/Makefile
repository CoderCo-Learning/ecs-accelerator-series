# GO

build-go-basic:
	docker build -t go-basic ./container-from-scratch/examples/go-basic
run-go-basic:
	docker run -p 8080:8080 go-basic

build-go-scratch:
	docker build -t go-scratch ./container-from-scratch/examples/go-scratch
run-go-scratch:
	docker run -p 8081:8080 go-scratch

build-go-distroless:
	docker build -t go-distroless ./container-from-scratch/examples/go-distroless
run-go-distroless:
	docker run -p 8082:8080 go-distroless



# NODE

build-node-basic:
	docker build -t node-basic ./container-from-scratch/examples/node-basic
run-node-basic:
	docker run -p 3000:3000 node-basic

build-node-prod:
	docker build -t node-prod ./container-from-scratch/examples/node-production
run-node-prod:
	docker run -p 3001:3000 node-prod



# PYTHON

build-python-basic:
	docker build -t python-basic ./container-from-scratch/examples/python-basic
run-python-basic:
	docker run -p 9000:9000 python-basic

build-python-slim:
	docker build -t python-slim ./container-from-scratch/examples/python-slim
run-python-slim:
	docker run -p 5001:5000 python-slim

build-python-distroless:
	docker build -t python-distroless ./container-from-scratch/examples/python-distroless
run-python-distroless:
	docker run -p 5002:5000 python-distroless



# STATIC NGINX

build-static:
	docker build -t static-site ./container-from-scratch/examples/static-nginx
run-static:
	docker run -p 8083:80 static-site



# BASH

build-bash:
	docker build -t bash-app ./container-from-scratch/examples/bash-script
run-bash:
	docker run bash-app



# JAVA

build-java:
	docker build -t java-app ./container-from-scratch/examples/java-basic
run-java:
	docker run -p 8084:8080 java-app



# C#

build-csharp:
	docker build -t csharp-app ./container-from-scratch/examples/csharp-basic
run-csharp:
	docker run -p 8085:8080 csharp-app



# PHP APACHE

build-php:
	docker build -t php-app ./container-from-scratch/examples/php-apache
run-php:
	docker run -p 8086:80 php-app



# OPEN SOURCE APPS

build-flask-todo:
	docker build -t flask-todo ./container-from-scratch/examples/opensource-app/flask-todo
run-flask-todo:
	docker run -p 8000:8000 flask-todo

build-go-chi:
	docker build -t go-chi ./container-from-scratch/examples/opensource-app/go-chi-api
run-go-chi:
	docker run -p 9000:9000 go-chi
test-go-chi:
	curl -X GET http://localhost:9000/hello


##### LIVE APPS #####

build-hackernews:
	docker build -t hackernews ./container-from-scratch/live/hackernews
run-hackernews:
	docker run -p 5001:5000 hackernews

build-it-tools:
	docker build -t it-tools ./container-from-scratch/live/it-tools
run-it-tools:	
	docker run -p 5002:80 it-tools

### ALL

# build-all:
# 	for dir in examples/*; do \
# 		if [ -f $$dir/Dockerfile ]; then \
# 			name=$$(basename $$dir); \
# 			echo "🔨 Building $$name..."; \
# 			docker build -t $$name $$dir; \
# 		fi \
# 	done


build-all:
	$(MAKE) -j 8 \
		build-go-basic \
		build-go-scratch \
		build-go-distroless \
		build-node-basic \
		build-node-prod \
		build-python-basic \
		build-python-slim \
		build-python-distroless \
		build-static \
		build-bash \
		build-java \
		build-csharp \
		build-php \
		build-flask-todo \
		build-go-chi

prune-all:
	docker system prune -a