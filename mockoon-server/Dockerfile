# ----------------------------
# 1️⃣ Base image
# ----------------------------
FROM node:22-alpine AS base

# Set working directory
WORKDIR /app

# ----------------------------
# 2️⃣ Install Mockoon CLI globally
# ----------------------------
RUN npm install -g @mockoon/cli

# ----------------------------
# 3️⃣ Copy your Mockoon environment file
# ----------------------------
COPY mockoon-environment.json /app/environment.json

# ----------------------------
# 4️⃣ Expose the desired port
# ----------------------------
EXPOSE 3000

# ----------------------------
# 5️⃣ Start Mockoon server
# ----------------------------
CMD ["mockoon-cli", "start", "--data", "/app/environment.json", "--port", "3000", "--hostname", "0.0.0.0"]
