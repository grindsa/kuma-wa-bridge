FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY vendor/wa_hack_cli /app/vendor/wa_hack_cli
COPY app /app/app

ENV PYTHONPATH=/app/vendor
ENV PORT=8080

EXPOSE 8080

CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "1", "--threads", "2", "app.main:app"]
