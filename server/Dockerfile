FROM node:18-alpine

WORKDIR /app

COPY package*.json ./
RUN npm install

COPY . .

ENV PORT=8080
EXPOSE 8080

# Use index.js as the single entrypoint
CMD ["node", "index.js"]
