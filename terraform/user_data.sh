#!/bin/bash
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

echo "Starting user_data setup for AI Inference Endpoint"

# Ensure docker is running (pre-installed on DL AMI)
systemctl enable docker
systemctl start docker

# Fix DNS for Docker daemon
mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<EOF
{"dns": ["8.8.8.8", "8.8.4.4"]}
EOF

# Install nvidia-container-toolkit
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
  tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
apt-get update && apt-get install -y nvidia-container-toolkit
nvidia-ctk runtime configure --runtime=docker

# Restart docker once with all configs applied, then wait until ready
systemctl restart docker
until docker info > /dev/null 2>&1; do
  echo "Waiting for Docker to be ready..."
  sleep 2
done
echo "Docker is ready"

# Pull the vLLM image
docker pull vllm/vllm-openai:latest

export HF_TOKEN="${hf_token}"
MODEL="${model_id}"

# Run vLLM with OpenAI compatible server
docker run -d --name vllm \
  --runtime nvidia --gpus all \
  --restart unless-stopped \
  -e HF_TOKEN=$HF_TOKEN \
  -v /opt/huggingface:/root/.cache/huggingface \
  -p 8000:8000 \
  --ipc=host \
  vllm/vllm-openai:latest \
  --model $MODEL \
  --max-model-len 2048 \
  --gpu-memory-utilization 0.90 \
  --enforce-eager \
  --host 0.0.0.0

echo "vLLM container started with model $MODEL"
