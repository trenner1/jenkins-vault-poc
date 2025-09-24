FROM hashicorp/vault:1.16

# Install curl for debugging and API testing
USER root
RUN apk add --no-cache curl

# Don't change user - let docker-compose handle it
# USER vault