FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY src/ ./src/
EXPOSE 4500
CMD ["node", "src/index.js"]