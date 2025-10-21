# Use a lightweight Node.js base image
FROM node:22-alpine AS build

# Create app directory
WORKDIR /usr/src/app

# Copy package files and install dependencies
COPY package*.json ./
RUN npm ci

# Copy the rest of the code
COPY . .

# Build TypeScript
RUN npm run build

# ------------------------------
# Runtime image
# ------------------------------
FROM node:22-alpine

WORKDIR /usr/src/app

# Copy only the built files and dependencies
COPY --from=build /usr/src/app/package*.json ./
RUN npm ci --omit=dev

COPY --from=build /usr/src/app/dist ./dist

EXPOSE 3000

CMD ["node", "dist/server.js"]
