FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY src/ ./src/
EXPOSE 4300
CMD ["node", "src/index.js"]