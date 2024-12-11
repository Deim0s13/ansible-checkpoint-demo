# Lightweight Python image as the base
FROM python:3.9-alpine

# Set enviornment variables to minimise interactions
ENV ANSIBLE_HOST_KEY_CHECKING=False

# Install system dependencies required for Ansible and Check Point modules
RUN apk add --no-cache \
    gcc \
    musl-dev \
    libffi-dev \
    openssl-dev \
    python3-dev \
    build-base \
    sshpass

# Install Ansible and the Check Point Ansible collection
RUN pip install --upgrade pip \
    && pip install ansible \
    && ansible-galaxy collection install check_point.mgmt

# Create a working directory
WORKDIR /app

# Copy Ansible playbooks and configuratios into the container
COPY ansible/ /app/ansible/
COPY ansible/inventory/ /app/ansible/inventory/

# Default command to run the container
ENTRYPOINT ["ansible-playbook", "-i", "/app/ansible/inventory/hosts.ini", "/app/ansible/playbooks/update_firewall.yml"]
