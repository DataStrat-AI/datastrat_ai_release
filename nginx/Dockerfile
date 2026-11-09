FROM nginx:alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Support running as unprivileged user
RUN touch /var/run/nginx.pid && \
    chown -R nginx:nginx /var/run/nginx.pid /etc/nginx/conf.d /var/cache/nginx /var/log/nginx

USER nginx
