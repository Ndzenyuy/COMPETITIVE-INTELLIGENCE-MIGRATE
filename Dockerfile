FROM python:3.11-slim

WORKDIR /app

# System deps: libpq-dev for psycopg2, gcc for compilation, curl for healthchecks
RUN apt-get update && apt-get install -y \
    libpq-dev \
    gcc \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies first (layer cache — only rebuilds when requirements change)
COPY app/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Bake the sentence-transformers model into the image at build time.
# Avoids a slow download (~90MB) on every container cold start.
RUN python -c "from sentence_transformers import SentenceTransformer; SentenceTransformer('all-MiniLM-L6-v2')"

# Copy application code
COPY app/ .

EXPOSE 8501

# Default command: Streamlit dashboard
# The agent task overrides this in its ECS task definition:
#   "command": ["python", "scripts/run_multiple.py"]
CMD ["streamlit", "run", "dashboard/app.py", \
     "--server.port", "8501", \
     "--server.address", "0.0.0.0"]
