# HTTPS server block template.
# scripts/aws/setup-https.sh renders this into nginx/conf.d/443-ssl.conf on the
# instance after a certificate has been issued, then reloads nginx.
#
# Placeholders replaced by the script:
#   __SERVER_NAME__    e.g. shop.example.com
#   __CERT_FULLCHAIN__ absolute path to fullchain.pem
#   __CERT_KEY__       absolute path to privkey.pem
#
# The HTTP server in conf.d/00-default.conf stays in place so ACME renewals and
# unknown Host headers keep working.

# ---------------------------------------------------------------- HTTP -> HTTPS
server {
    listen       80;
    listen       [::]:80;
    server_name  __SERVER_NAME__;

    location ^~ /.well-known/acme-challenge/ {
        root         /var/www/certbot;
        default_type "text/plain";
        allow        all;
    }

    location / {
        return 301 https://$host$request_uri;
    }
}

# ---------------------------------------------------------------------- HTTPS
server {
    listen       443 ssl;
    listen       [::]:443 ssl;
    http2        on;
    server_name  __SERVER_NAME__;

    ssl_certificate     __CERT_FULLCHAIN__;
    ssl_certificate_key __CERT_KEY__;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache   shared:SSL:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;

    # Secure cookies (the admin session) are only sent over HTTPS, so the owner
    # dashboard becomes fully functional once this block is active.
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

    add_header X-Content-Type-Options "nosniff"                            always;
    add_header X-Frame-Options        "SAMEORIGIN"                         always;
    add_header Referrer-Policy        "strict-origin-when-cross-origin"     always;
    add_header Permissions-Policy     "geolocation=(), microphone=(), camera=()" always;

    limit_conn addr 60;

    location = /nginx-health {
        access_log   off;
        default_type text/plain;
        return 200 "ok\n";
    }

    location ^~ /.well-known/acme-challenge/ {
        root         /var/www/certbot;
        default_type "text/plain";
        allow        all;
    }

    location /api/ {
        limit_except GET HEAD POST DELETE OPTIONS {
            deny all;
        }

        include /etc/nginx/conf-src/snippets/proxy-common.conf;

        proxy_pass              http://api_gateway;
        proxy_set_header        Accept-Encoding gzip;

        proxy_connect_timeout   10s;
        proxy_send_timeout      120s;
        proxy_read_timeout      120s;
        proxy_buffering         on;
        proxy_request_buffering off;

        proxy_intercept_errors  on;
        error_page 502 503 504 = @api_unavailable;
    }

    location @api_unavailable {
        default_type application/json;
        add_header   Cache-Control "no-store" always;
        return       503 '{"error":"Service temporarily unavailable"}';
    }

    location / {
        include /etc/nginx/conf-src/snippets/proxy-common.conf;
        proxy_pass http://frontend_app;
    }

    location ^~ /assets/ {
        include /etc/nginx/conf-src/snippets/proxy-common.conf;

        proxy_pass http://frontend_app;
        expires    7d;

        add_header Cache-Control          "public, max-age=604800";
        add_header X-Content-Type-Options "nosniff" always;
    }
}
