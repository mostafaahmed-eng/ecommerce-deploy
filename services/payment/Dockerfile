FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev && npm cache clean --force
COPY src/ ./src/
# Writable defaults for the two durable paths. In production both are replaced
# by bind mounts from the EBS-backed host filesystem:
#   /app/data               -> orders / owner sessions / notification index
#   /app/uploads/receipts   -> uploaded payment receipts
RUN mkdir -p /app/uploads/receipts /app/data \
    && chown -R node:node /app/uploads /app/data
USER node
EXPOSE 4200
CMD ["node", "src/index.js"]
