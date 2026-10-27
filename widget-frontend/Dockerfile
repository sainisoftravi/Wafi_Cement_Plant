FROM node:22-alpine

ENV NODE_ENV=production
WORKDIR /app

COPY package*.json ./
RUN npm ci --omit=dev

COPY server.js ./
COPY *.html ./
COPY js ./js

EXPOSE 4173
CMD ["npm", "start"]
