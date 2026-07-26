# 🌿 PurePick: AI-Powered Cosmetic & Skin Analysis App

![Project Status](https://img.shields.io/badge/Status-Active-success)
![Python Version](https://img.shields.io/badge/Python-3.9%2B-blue)
![Django Version](https://img.shields.io/badge/Django-DRF-green)
![PyTorch](https://img.shields.io/badge/PyTorch-EfficientNet-red)

## 📖 Summary
PurePick is an intelligent, AI-driven mobile application and backend system designed to help users make informed, personalized decisions about their skincare routines and cosmetic product choices. By combining deep learning, optical character recognition (OCR), and complex data matching, PurePick bridges the gap between confusing chemical ingredient labels and personal skin health. 

## 💡 Project Description
Navigating the world of skincare can be overwhelming. PurePick solves this by offering a comprehensive digital assistant that analyzes user skin conditions and evaluates cosmetic products for safety. 

Operating on a microservices-inspired architecture, the robust backend processes heavy machine learning inferences asynchronously. Whether a user is scanning a barcode, uploading a photo of an ingredient label, or taking a selfie for skin analysis, the PurePick engine cross-references real-time data against the user's custom health profile to provide personalized risk scores, AI-generated tips, and contextual skincare advice.

## ✨ Key Features

*   **🔍 AI Skin Condition Detection:** Users upload a selfie, and the system uses a custom-trained deep learning model to detect up to 14 different skin conditions simultaneously (e.g., acne, redness, dryness).
*   **📸 Smart Label OCR:** Extracts and analyzes raw text from physical cosmetic ingredient labels using advanced CRAFT text detection and CRNN recognition.
*   **🛒 Barcode Ingredient Scanning:** Fetches product data via the Open Beauty Facts API and cross-references ingredients against user-specific allergies using fuzzy string matching to generate a "Safety Risk Score."
*   **💬 Context-Aware AI Chat:** An integrated LLM skincare assistant that tailors its advice dynamically based on the user's saved `HealthProfile` and recent scan history.
*   **⚡ High-Performance Asynchronous Processing:** Heavy machine learning tasks (OCR, Face Analysis) are offloaded to isolated background queues, ensuring the main API remains fast and non-blocking for the mobile client.

## 🛠️ Tools & Technologies Used

### Backend & API Core
*   **Python:** Core programming language.
*   **Django & Django REST Framework (DRF):** For building the robust, scalable RESTful web API.
*   **Gunicorn:** WSGI HTTP Server for deployment.

### AI, Machine Learning & Computer Vision
*   **PyTorch & timm:** Powering the EfficientNet-B4 deep learning model for skin analysis.
*   **EasyOCR & OpenCV:** For image preprocessing, contrast enhancement (CLAHE), and text extraction from product labels.
*   **RapidFuzz:** For rapid fuzzy string matching of cosmetic ingredients against user allergy profiles.

### Database, Caching & Task Queues
*   **PostgreSQL 16:** Primary relational database managing user profiles, auth tokens, and historical scan records.
*   **Redis 7:** High-speed in-memory data store acting as both a message broker for async tasks and a caching layer for AI recommendations (4-hour TTL).
*   **Celery:** Distributed task queue managing dual worker pools (`worker_ml` for GPU/CPU heavy tasks, `worker_default` for standard API polling).

### Security & Integrations
*   **Argon2:** Advanced hashing algorithm for password security.
*   **JWT (SimpleJWT):** For secure, token-based stateless authentication.
*   **Google OAuth 2.0:** Integrated for seamless third-party login.

## 🏗️ System Architecture Flow
1. **Client Request:** The Flutter mobile app sends an API request (e.g., image upload).
2. **Task Delegation:** The Django API accepts the request (HTTP 202), saves the initial state in PostgreSQL, and pushes a task to the Redis message broker.
3. **Background Processing:** A dedicated Celery worker picks up the task, runs the ML inference (EasyOCR or EfficientNet), and saves the final result back to the database.
4. **Client Polling:** The mobile app polls the backend, retrieving the analyzed data once the task status reads `SUCCESS`.
