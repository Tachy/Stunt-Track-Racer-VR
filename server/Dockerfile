# Stunt Track Racer VR online server: a few MB, no physics.
#   docker build -t stunt-racer-server server/
#   docker run -d --restart=unless-stopped -p 27015:27015/udp stunt-racer-server
FROM golang:1.22-alpine AS build
WORKDIR /src
COPY go.mod ./
COPY *.go ./
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /stunt-racer-server .

FROM scratch
COPY --from=build /stunt-racer-server /stunt-racer-server
EXPOSE 27015/udp
USER 65534:65534
ENTRYPOINT ["/stunt-racer-server", "-port", "27015", "-v"]
