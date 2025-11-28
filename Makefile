# GO

build-go-basic:
	docker build -t go-basic ./examples/go-basic
run-go-basic:
	docker run -p 8080:8080 go-basic

build-go-scratch:
	docker build -t go-scratch ./examples/go-scratch
run-go-scratch:
	docker run -p 8081:8080 go-scratch

build-go-distroless:
	docker build -t go-distroless ./examples/go-distroless
run-go-distroless:
	docker run -p 8082:8080 go-distroless



# NODE

build-node-basic:
	docker build -t node-basic ./examples/node-basic
run-node-basic:
	docker run -p 3000:3000 node-basic

build-node-prod:
	docker build -t node-prod ./examples/node-production
run-node-prod:
	docker run -p 3001:3000 node-prod



# PYTHON

build-python-basic:
	docker build -t python-basic ./examples/python-basic
run-python-basic:
	docker run -p 9000:9000 python-basic

build-python-slim:
	docker build -t python-slim ./examples/python-slim
run-python-slim:
	docker run -p 5001:5000 python-slim

build-python-distroless:
	docker build -t python-distroless ./examples/python-distroless
run-python-distroless:
	docker run -p 5002:5000 python-distroless



# STATIC NGINX

build-static:
	docker build -t static-site ./examples/static-nginx
run-static:
	docker run -p 8083:80 static-site



# BASH

build-bash:
	docker build -t bash-app ./examples/bash-script
run-bash:
	docker run bash-app



# JAVA

build-java:
	docker build -t java-app ./examples/java-basic
run-java:
	docker run -p 8084:8080 java-app



# C#

build-csharp:
	docker build -t csharp-app ./examples/csharp-basic
run-csharp:
	docker run -p 8085:8080 csharp-app



# PHP APACHE

build-php:
	docker build -t php-app ./examples/php-apache
run-php:
	docker run -p 8086:80 php-app



# OPEN SOURCE APPS

build-flask-todo:
	docker build -t flask-todo ./examples/opensource-app/flask-todo
run-flask-todo:
	docker run -p 8000:8000 flask-todo

build-go-chi:
	docker build -t go-chi ./examples/opensource-app/go-chi-api
run-go-chi:
	docker run -p 9000:9000 go-chi
test-go-chi:
	curl -X GET http://localhost:9000/hello
