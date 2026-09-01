FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev && npm cache clean --force
COPY src/ ./src/
COPY data/ ./data/
USER node
EXPOSE 4500
CMD ["node", "src/index.js"]
