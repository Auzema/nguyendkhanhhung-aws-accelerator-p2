# ---- build stage: compile the Go binary (no Go needed on your machine) ----
FROM golang:1.24-alpine AS build
WORKDIR /src
# Copy sources first, then resolve deps + build. go mod tidy fetches the
# aws-sdk-go-v2 modules and writes go.sum inside the build (needs network).
COPY go.mod ./
COPY main.go ./
COPY static ./static
RUN go mod tidy
RUN CGO_ENABLED=0 GOOS=linux go build -o /out/media .

# ---- run stage: tiny image with just the binary + CA certs for HTTPS to S3 ----
FROM alpine:3.20
RUN apk add --no-cache ca-certificates
COPY --from=build /out/media /usr/local/bin/media
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/media"]
