# HIMS

Simple starter code. Backend = FastAPI. Frontend = Streamlit. Database = PostgreSQL (Aiven).

## 1. Set up (one time)
```bash
python -m venv .venv
# Windows: .venv\Scripts\activate     Mac/Linux: source .venv/bin/activate
pip install -r requirements.txt
```
Copy `.env.example` to `.env`. Put the real Aiven database URL in `.env`.

## 2. Run the backend
```bash
cd backend
uvicorn app.main:app --reload
```
Open http://localhost:8000/docs to see and try all endpoints.

## 3. Run the frontend (in a second terminal)
```bash
streamlit run frontend/app.py
```
Open http://localhost:8501

## Where to write code
Each module (A to F) has 3 files in `backend/app/modules/<module>/`:
- `router.py`     - the endpoints (URLs). Receives the request, sends the reply.
- `service.py`    - the business rules.
- `repository.py` - reads and writes the database tables of this module.

Screens go in `frontend/pages/`.
