FROM node:20-alpine

WORKDIR /app

COPY package.json ./
COPY server.js ./

ENV HOST=0.0.0.0
ENV PORT=17511
ENV ROOM_TTL=1800000
ENV NODE_ENV=production

EXPOSE 17511/tcp

USER node

CMD ["node", "server.js"]
