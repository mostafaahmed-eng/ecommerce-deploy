FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev && npm cache clean --force
COPY src/ ./src/
USER node
EXPOSE 4600
CMD ["node", "src/index.js"]
