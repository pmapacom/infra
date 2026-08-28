# Gateway image — nginx with the PMapa gateway config baked in, so prod needs no
# host bind mounts (which are fragile under Portainer git stacks).
#   docker build -t ghcr.io/pmapacom/gateway:latest env/gateway
FROM nginx:alpine
COPY nginx.conf /etc/nginx/nginx.conf
COPY snippets/ /etc/nginx/gateway/snippets/
EXPOSE 8080
