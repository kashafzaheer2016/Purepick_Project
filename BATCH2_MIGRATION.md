# Batch 2 — Async Workers Migration Guide

## What Changed

### Problem this solves
Django WSGI is synchronous. Before this batch:
- OCR (EasyOCR): **3–8s** blocked the entire Django worker thread
- Skin analysis (ResNet-50): **5–15s** blocked the entire Django worker thread
- Gemini calls: **1–4s** blocked the entire Django worker thread
- At 4 gunicorn workers: **5 concurrent users = total system hang**

### Solution
All heavy operations now run in Celery workers. HTTP requests return `task_id`
in under **50ms**. Flutter polls `/api/task/<task_id>/` every 1.5s until done.

---

## New Files

| File | Purpose |
|---|---|
| `backend/purepick_core/celery.py` | Celery app factory |
| `backend/purepick_core/__init__.py` | Auto-load Celery on Django start |
| `backend/purepick_core/task_views.py` | Task status polling endpoint |
| `backend/scanner/tasks.py` | OCR, ingredient analysis, Gemini tasks |
| `backend/skin_analysis/tasks.py` | ResNet-50 skin analysis task |
| `backend/Dockerfile` | Backend container image |
| `docker-compose.yml` | Full local dev stack |
| `mobile_app/lib/services/task_poller.dart` | Flutter polling service |

## Modified Files

| File | Change |
|---|---|
| `purepick_core/settings/base.py` | Added Celery + Redis config block |
| `scanner/views.py` | All heavy endpoints now enqueue tasks, return 202 |
| `skin_analysis/views.py` | analyze_face enqueues task, returns 202 |
| `scanner/urls.py` | Added `/api/task/<task_id>/` polling endpoint |
| `requirements.txt` | Added `celery==5.4.0`, `redis==5.0.4` |
| `mobile_app/lib/services/api_service.dart` | Accepts 200 + 202; authHeaders made public |
| `mobile_app/lib/screens/scan_screen.dart` | Polls task_id, shows live status |
| `mobile_app/lib/screens/analysis_screen.dart` | Polls task_id, animated status |
| `mobile_app/lib/screens/ai_chat_screen.dart` | Polls task_id for Gemini reply |
| `mobile_app/lib/screens/ai_tips_screen.dart` | Polls task_id for tips |
| `mobile_app/lib/screens/skin_analysis_screen.dart` | Polls task_id, live status |

---

## Setup

### Option A — Docker (recommended)
```bash
cp backend/.env.example backend/.env
# Edit .env with your secrets + add: REDIS_URL=redis://redis:6379/0

docker-compose up -d redis db
docker-compose run api python manage.py migrate
docker-compose up
```

### Option B — Manual
```bash
# 1. Install Redis
brew install redis && redis-server   # macOS
sudo apt install redis-server && sudo systemctl start redis   # Ubuntu

# 2. Install new Python deps
cd backend
pip install celery==5.4.0 redis==5.0.4

# 3. Add to .env
echo "REDIS_URL=redis://localhost:6379/0" >> .env

# 4. Migrate
python manage.py migrate

# 5. Start workers (3 terminals)
# Terminal 1 — Django
python manage.py runserver

# Terminal 2 — ML worker (OCR + skin analysis)
celery -A purepick_core worker --queues ml --concurrency=2 --loglevel=info

# Terminal 3 — Default worker (Gemini, light tasks)
celery -A purepick_core worker --queues default --concurrency=4 --loglevel=info

# Optional: Flower monitoring dashboard at http://localhost:5555
celery -A purepick_core flower
```

---

## New Request Lifecycle

### Before (synchronous — blocking)
```
POST /api/scan-label/
  → Django worker thread locked for 3–8s (OCR)
  → Response after 3–8s
```

### After (async — non-blocking)
```
POST /api/scan-label/
  → Django saves temp file
  → Enqueues task to Redis (< 10ms)
  → Returns {"task_id": "abc123", "status": "PENDING"}  in < 50ms

Flutter polls GET /api/task/abc123/ every 1.5s:
  → {"status": "PENDING"}
  → {"status": "STARTED"}
  → {"status": "SUCCESS", "result": {...full report...}}
```

---

## Task Queue Routing

| Task | Queue | Why |
|---|---|---|
| `run_ocr_and_analyze` | `ml` | CPU-heavy, EasyOCR ~3–8s |
| `run_skin_analysis` | `ml` | CPU-heavy, ResNet-50 ~5–15s |
| `call_gemini_chat` | `default` | External API, fast I/O |
| `call_gemini_tips` | `default` | External API, fast I/O |
| `run_ingredient_analysis` | `default` | Rule engine, fast compute |

---

## Monitoring
Flower dashboard at `http://localhost:5555` shows:
- Active tasks per worker
- Task success/failure rates
- Queue lengths
- Worker memory usage
