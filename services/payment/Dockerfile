FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev && npm cache clean --force
COPY src/ ./src/
RUN mkdir -p /app/uploads && chown -R node:node /app/uploads
USER node
EXPOSE 4200
CMD ["node", "src/index.js"]
