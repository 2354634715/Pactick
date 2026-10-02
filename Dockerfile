FROM golang:1.26-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/server ./cmd/server
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/migrate ./cmd/migrate
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/healthcheck ./cmd/healthcheck

FROM gcr.io/distroless/static-debian12:nonroot
COPY LICENSE THIRD_PARTY_NOTICES.md /licenses/
COPY third_party/licenses /licenses/third-party/
COPY --from=build /out/server /server
COPY --from=build /out/migrate /migrate
COPY --from=build /out/healthcheck /healthcheck
EXPOSE 8080
USER nonroot:nonroot
STOPSIGNAL SIGTERM
HEALTHCHECK --interval=30s --timeout=3s --start-period=15s --retries=3 CMD ["/healthcheck"]
ENTRYPOINT ["/server"]
