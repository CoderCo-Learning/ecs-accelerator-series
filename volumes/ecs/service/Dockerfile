FROM golang:1.22-alpine AS builder
WORKDIR /app
COPY . .
RUN go build -o app .

FROM alpine:3.19
WORKDIR /app
COPY --from=builder /app/app .
COPY --from=builder /app/static ./static
EXPOSE 8080
CMD ["./app"]

## Old conf
# FROM golang:1.22-alpine AS builder
# WORKDIR /app
# COPY . .
# RUN go build -o app .

# FROM alpine:3.19
# WORKDIR /app
# COPY --from=builder /app/app .
# EXPOSE 8080
# CMD ["./app"]