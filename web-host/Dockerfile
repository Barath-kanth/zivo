# Serve Flutter web build on Cloud Run (scale-to-zero, free-tier friendly).
FROM nginx:1.27-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY build/web /usr/share/nginx/html
EXPOSE 8080
CMD ["nginx", "-g", "daemon off;"]
