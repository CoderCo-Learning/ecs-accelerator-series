FROM nginx:alpine
COPY README.md /usr/share/nginx/html/index.html
HEALTHCHECK --interval=10s --timeout=3s CMD wget -qO- http://localhost/ || exit 1
EXPOSE 80
