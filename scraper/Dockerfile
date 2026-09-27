FROM python:3.12-slim

WORKDIR /app
COPY scraper/requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r requirements.txt
COPY scraper /app/scraper

USER 10001
EXPOSE 8000
CMD ["uvicorn", "scraper.app:app", "--host", "0.0.0.0", "--port", "8000", "--no-access-log"]
