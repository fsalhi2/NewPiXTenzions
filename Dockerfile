FROM node:22-slim

# 1. Install system dependencies
RUN apt-get update && apt-get install -y \
    git \
    expect \
    tmux \
    curl \
    ca-certificates \
    docker.io \
    && rm -rf /var/lib/apt/lists/*

# 2. Install pi
RUN npm install -g @earendil-works/pi-coding-agent

# 3. Set working directory
WORKDIR /app

# 4. Copy the entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["pi"]
