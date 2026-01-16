FROM node:22-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
RUN mkdir -p /data
EXPOSE 3000
CMD ["node", "app.js"]
