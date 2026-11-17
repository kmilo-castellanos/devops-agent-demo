FROM node:22-alpine
WORKDIR /app
COPY package.json ./
COPY server.js ./
COPY src ./src
COPY public ./public
ARG GIT_SHA=dev
ENV NODE_ENV=production PORT=3000 GIT_SHA=$GIT_SHA
USER node
EXPOSE 3000
CMD ["node", "server.js"]
